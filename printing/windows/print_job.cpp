/*
 * Copyright (C) 2017, David PHAM-VAN <dev.nfet.net@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "print_job.h"

#include "printing.h"

#include <fpdfview.h>
#include <objbase.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <tchar.h>
#include <cmath>
#include <codecvt>
#include <fstream>
#include <iterator>
#include <limits>
#include <numeric>

namespace nfet {

const auto pdfDpi = 72;

std::string toUtf8(std::wstring wstr) {
  int cbMultiByte = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, nullptr,
                                        0, nullptr, nullptr);
  LPSTR lpMultiByteStr = (LPSTR)malloc(cbMultiByte);
  cbMultiByte =
      WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, lpMultiByteStr,
                          cbMultiByte, nullptr, nullptr);
  std::string ret = lpMultiByteStr;
  free(lpMultiByteStr);
  return ret;
}

std::string toUtf8(TCHAR* tstr) {
#ifndef UNICODE
#error "Non unicode build not supported"
#endif

  if (!tstr) {
    return std::string{};
  }

  return toUtf8(std::wstring{tstr});
}

std::wstring fromUtf8(std::string str) {
  auto len = MultiByteToWideChar(CP_UTF8, 0, str.c_str(),
                                 static_cast<int>(str.length()), nullptr, 0);
  if (len <= 0) {
    return L"";
  }

  auto wstr = std::wstring{};
  wstr.resize(len);
  MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.length()),
                      &wstr[0], len);

  return wstr;
}

// Match known PdfPageFormat dimensions (in PDF points) to a Windows
// DMPAPER_* constant.  Returns 0 when no standard size matches.
static short matchStandardPaperSize(double widthPt, double heightPt) {
  // Portrait dimensions (short × long) in tenths of a millimetre.
  auto shortSide =
      static_cast<short>(round((std::min)(widthPt, heightPt) * 254.0 / 72.0));
  auto longSide =
      static_cast<short>(round((std::max)(widthPt, heightPt) * 254.0 / 72.0));

  // Allow ±2 mm tolerance for floating-point rounding.
  auto match = [](short a, short b) -> bool {
    return std::abs(a - b) <= 20;
  };

  // A3: 297 × 420 mm
  if (match(shortSide, 2970) && match(longSide, 4200))
    return DMPAPER_A3;
  // A4: 210 × 297 mm
  if (match(shortSide, 2100) && match(longSide, 2970))
    return DMPAPER_A4;
  // A5: 148 × 210 mm
  if (match(shortSide, 1480) && match(longSide, 2100))
    return DMPAPER_A5;
  // A6: 105 × 148 mm
  if (match(shortSide, 1050) && match(longSide, 1480))
    return DMPAPER_A6;
  // US Letter: 215.9 × 279.4 mm
  if (match(shortSide, 2159) && match(longSide, 2794))
    return DMPAPER_LETTER;
  // US Legal: 215.9 × 355.6 mm
  if (match(shortSide, 2159) && match(longSide, 3556))
    return DMPAPER_LEGAL;

  return 0;
}

PrintJob::PrintJob(Printing* printing, int index)
    : printing{printing}, index{index} {}

bool PrintJob::printPdf(const std::string& name,
                        std::string printer,
                        double width,
                        double height,
                        bool usePrinterSettings) {
  documentName = name;
  isRollPaper = std::isinf(height) || std::isinf(width);

  std::size_t dmSize = sizeof(DEVMODE);
  std::size_t dmExtra = 0;

  if (!printer.empty()) {
    dmExtra = DeviceCapabilities(fromUtf8(printer).c_str(), NULL, DC_EXTRA,
                                 NULL, NULL);
  }

  auto dm = static_cast<DEVMODE*>(GlobalAlloc(0, dmSize + dmExtra));

  if (usePrinterSettings) {
    // Use the printer's default configuration (paper size, margins, etc.)
    // without overriding anything — honour whatever the driver reports.
    bool gotDefaults = false;
    if (!printer.empty()) {
      HANDLE hPrinter = nullptr;
      auto wPrinter = fromUtf8(printer);
      if (OpenPrinter(const_cast<LPWSTR>(wPrinter.c_str()), &hPrinter,
                      nullptr)) {
        LONG needed = DocumentProperties(
            nullptr, hPrinter, const_cast<LPWSTR>(wPrinter.c_str()), nullptr,
            nullptr, 0);
        if (needed > 0) {
          auto defaultDm = static_cast<DEVMODE*>(GlobalAlloc(0, needed));
          if (defaultDm &&
              DocumentProperties(nullptr, hPrinter,
                                 const_cast<LPWSTR>(wPrinter.c_str()),
                                 defaultDm, nullptr,
                                 DM_OUT_BUFFER) == IDOK) {
            GlobalFree(dm);
            dm = defaultDm;
            gotDefaults = true;
          } else {
            GlobalFree(defaultDm);
          }
        }
        ClosePrinter(hPrinter);
      }
    }
    if (isRollPaper) {
      // Roll paper always needs explicit width; the height is set per-page
      // in writeJob via ResetDC.
      if (!gotDefaults) {
        ZeroMemory(dm, sizeof(DEVMODE));
        dm->dmSize = (WORD)dmSize;
        dm->dmDriverExtra = (WORD)dmExtra;
      }
      dm->dmFields |= DM_ORIENTATION | DM_PAPERLENGTH | DM_PAPERWIDTH;
      dm->dmFields &= ~DM_PAPERSIZE;
      dm->dmOrientation = DMORIENT_PORTRAIT;
      dm->dmPaperWidth = static_cast<short>(round(width * 254 / pdfDpi));
      dm->dmPaperLength = dm->dmPaperWidth;  // Initial square size
    } else if (!gotDefaults) {
      // No printer specified or couldn't retrieve defaults — pass nullptr
      // so CreateDC / PrintDlg uses the driver's built-in defaults.
      GlobalFree(dm);
      dm = nullptr;
    }
  } else {
    ZeroMemory(dm, sizeof(DEVMODE));
    dm->dmSize = (WORD)dmSize;
    dm->dmDriverExtra = (WORD)dmExtra;
    if (isRollPaper) {
      // Roll/continuous paper: use width from PdfPageFormat, height set per-page
      dm->dmFields = DM_ORIENTATION | DM_PAPERLENGTH | DM_PAPERWIDTH;
      dm->dmOrientation = DMORIENT_PORTRAIT;
      dm->dmPaperWidth = static_cast<short>(round(width * 254 / pdfDpi));
      dm->dmPaperLength = dm->dmPaperWidth;  // Initial square size
    } else {
      auto paperSize = matchStandardPaperSize(width, height);
      if (paperSize > 0) {
        // Use the named paper size — drivers handle DM_PAPERSIZE with
        // DM_ORIENTATION far more reliably than custom dimensions.
        dm->dmFields = DM_ORIENTATION | DM_PAPERSIZE;
        dm->dmPaperSize = paperSize;
        dm->dmOrientation =
            (width > height) ? DMORIENT_LANDSCAPE : DMORIENT_PORTRAIT;
      } else {
        // Custom paper: pass explicit dimensions in portrait form.
        dm->dmFields = DM_ORIENTATION | DM_PAPERLENGTH | DM_PAPERWIDTH;
        auto shortSide = static_cast<short>(
            round((std::min)(width, height) * 254 / pdfDpi));
        auto longSide = static_cast<short>(
            round((std::max)(width, height) * 254 / pdfDpi));
        dm->dmPaperWidth = shortSide;
        dm->dmPaperLength = longSide;
        dm->dmOrientation =
            (width > height) ? DMORIENT_LANDSCAPE : DMORIENT_PORTRAIT;
      }
    }
  }

  if (printer.empty()) {
    PRINTDLG pd;

    // Initialize PRINTDLG
    ZeroMemory(&pd, sizeof(pd));
    pd.lStructSize = sizeof(pd);

    // Initialize PRINTDLG
    pd.hwndOwner = nullptr;
    pd.hDevMode = dm;
    pd.hDevNames = nullptr;  // Don't forget to free or store hDevNames.
    pd.hDC = nullptr;
    pd.Flags = PD_USEDEVMODECOPIES | PD_RETURNDC | PD_PRINTSETUP |
               PD_NOSELECTION | PD_NOPAGENUMS;
    pd.nCopies = 1;
    pd.nFromPage = 0xFFFF;
    pd.nToPage = 0xFFFF;
    pd.nMinPage = 1;
    pd.nMaxPage = 0xFFFF;

    auto r = PrintDlg(&pd);

    if (r != 1) {
      printing->onCompleted(this, false, "");
      DeleteDC(hDC);
      GlobalFree(hDevNames);
      ClosePrinter(hDevMode);
      return true;
    }

    hDC = pd.hDC;
    hDevMode = pd.hDevMode;
    hDevNames = pd.hDevNames;

  } else {
    hDC = CreateDC(TEXT("WINSPOOL"), fromUtf8(printer).c_str(), nullptr, dm);
    if (!hDC) {
      return false;
    }
    hDevMode = dm;
    hDevNames = nullptr;
  }

  auto dpiX = static_cast<double>(GetDeviceCaps(hDC, LOGPIXELSX)) / pdfDpi;
  auto dpiY = static_cast<double>(GetDeviceCaps(hDC, LOGPIXELSY)) / pdfDpi;
  auto pageWidth =
      static_cast<double>(GetDeviceCaps(hDC, PHYSICALWIDTH)) / dpiX;
  auto pageHeight =
      static_cast<double>(GetDeviceCaps(hDC, PHYSICALHEIGHT)) / dpiY;
  auto printableWidth = static_cast<double>(GetDeviceCaps(hDC, HORZRES)) / dpiX;
  auto printableHeight =
      static_cast<double>(GetDeviceCaps(hDC, VERTRES)) / dpiY;
  auto marginLeft =
      static_cast<double>(GetDeviceCaps(hDC, PHYSICALOFFSETX)) / dpiX;
  auto marginTop =
      static_cast<double>(GetDeviceCaps(hDC, PHYSICALOFFSETY)) / dpiY;
  auto marginRight = pageWidth - printableWidth - marginLeft;
  auto marginBottom = pageHeight - printableHeight - marginTop;

  if (isRollPaper) {
    // For roll paper, pass infinity height back to Dart so the PDF
    // page auto-sizes to fit content
    printing->onLayout(this, pageWidth,
                       std::numeric_limits<double>::infinity(), marginLeft,
                       marginTop, marginRight, marginBottom);
  } else {
    printing->onLayout(this, pageWidth, pageHeight, marginLeft, marginTop,
                       marginRight, marginBottom);
  }
  return true;
}

std::vector<Printer> PrintJob::listPrinters() {
  LPTSTR defaultPrinter;
  DWORD size = 0;
  GetDefaultPrinter(nullptr, &size);

  defaultPrinter = static_cast<LPTSTR>(malloc(size * sizeof(TCHAR)));
  if (!GetDefaultPrinter(defaultPrinter, &size)) {
    size = 0;
  }

  auto printers = std::vector<Printer>{};
  DWORD needed = 0;
  DWORD returned = 0;
  const auto flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;

  EnumPrinters(flags, nullptr, 2, nullptr, 0, &needed, &returned);

  auto buffer = (PRINTER_INFO_2*)malloc(needed);
  if (!buffer) {
    return printers;
  }

  auto result = EnumPrinters(flags, nullptr, 2, (LPBYTE)buffer, needed, &needed,
                             &returned);

  if (result == 0) {
    free(buffer);
    return printers;
  }

  for (DWORD i = 0; i < returned; i++) {
    printers.push_back(Printer{
        toUtf8(buffer[i].pPrinterName), toUtf8(buffer[i].pPrinterName),
        toUtf8(buffer[i].pDriverName), toUtf8(buffer[i].pLocation),
        toUtf8(buffer[i].pComment),
        size > 0 && _tcsncmp(buffer[i].pPrinterName, defaultPrinter, size) == 0,
        (buffer[i].Status &
         (PRINTER_STATUS_NOT_AVAILABLE | PRINTER_STATUS_ERROR |
          PRINTER_STATUS_OFFLINE | PRINTER_STATUS_PAUSED)) == 0});
  }

  free(buffer);
  free(defaultPrinter);
  return printers;
}

void PrintJob::writeJob(std::vector<uint8_t> data) {
  auto dpiX = static_cast<double>(GetDeviceCaps(hDC, LOGPIXELSX)) / pdfDpi;
  auto dpiY = static_cast<double>(GetDeviceCaps(hDC, LOGPIXELSY)) / pdfDpi;

  DOCINFO docInfo;

  ZeroMemory(&docInfo, sizeof(docInfo));
  docInfo.cbSize = sizeof(docInfo);

  auto docName = fromUtf8(documentName);
  docInfo.lpszDocName = docName.c_str();

  auto r = StartDoc(hDC, &docInfo);

  FPDF_LIBRARY_CONFIG config;
  config.version = 2;
  config.m_pUserFontPaths = nullptr;
  config.m_pIsolate = nullptr;
  config.m_v8EmbedderSlot = 0;
  FPDF_InitLibraryWithConfig(&config);

  auto doc = FPDF_LoadMemDocument64(data.data(), data.size(), nullptr);
  if (!doc) {
    FPDF_DestroyLibrary();
    return;
  }

  auto pages = FPDF_GetPageCount(doc);
  auto marginLeft = GetDeviceCaps(hDC, PHYSICALOFFSETX);
  auto marginTop = GetDeviceCaps(hDC, PHYSICALOFFSETY);

  for (auto pageNum = 0; pageNum < pages; pageNum++) {
    auto page = FPDF_LoadPage(doc, pageNum);
    if (!page) {
      continue;
    }

    auto pdfWidth = FPDF_GetPageWidth(page);
    auto pdfHeight = FPDF_GetPageHeight(page);

    // For roll/continuous paper, update the printer DC page size
    // to match the actual PDF page dimensions before printing
    if (isRollPaper) {
      auto pDm = static_cast<DEVMODE*>(GlobalLock(hDevMode));
      if (pDm) {
        pDm->dmFields |= DM_PAPERLENGTH | DM_PAPERWIDTH;
        pDm->dmFields &= ~DM_PAPERSIZE;
        pDm->dmPaperWidth =
            static_cast<short>(round(pdfWidth * 254.0 / pdfDpi));
        pDm->dmPaperLength =
            static_cast<short>(round(pdfHeight * 254.0 / pdfDpi));
        ResetDC(hDC, pDm);
        GlobalUnlock(hDevMode);
      }
      // Do NOT re-query PHYSICALOFFSETX/PHYSICALOFFSETY after ResetDC.
      // The PDF content was laid out based on the margins reported via
      // onLayout (from the initial DC). If ResetDC changes the physical
      // offset, using the new values here would create a mismatch —
      // content positioned near the left edge (based on the original
      // margins) would be shifted into the unprintable area and clipped.
      // Keep the initial marginLeft/marginTop for consistent rendering.
      dpiX = static_cast<double>(GetDeviceCaps(hDC, LOGPIXELSX)) / pdfDpi;
      dpiY = static_cast<double>(GetDeviceCaps(hDC, LOGPIXELSY)) / pdfDpi;
    }

    StartPage(hDC);

    // Get the printer's actual printable area (in device pixels)
    auto printableWidthPx = GetDeviceCaps(hDC, HORZRES);
    auto printableHeightPx = GetDeviceCaps(hDC, VERTRES);

    int bWidth = static_cast<int>(pdfWidth * dpiX);
    int bHeight = static_cast<int>(pdfHeight * dpiY);

    // Scale down to fit if the PDF page is larger than the printer's
    // printable area (e.g. 80mm PDF on a 72mm thermal printer).
    // Only scale down, never scale up.
    double scale = 1.0;
    if (bWidth > 0 && bHeight > 0) {
      double scaleX = (bWidth > printableWidthPx)
                          ? static_cast<double>(printableWidthPx) / bWidth
                          : 1.0;
      double scaleY = (bHeight > printableHeightPx)
                          ? static_cast<double>(printableHeightPx) / bHeight
                          : 1.0;
      scale = (std::min)(scaleX, scaleY);
      if (scale < 1.0) {
        bWidth = static_cast<int>(bWidth * scale);
        bHeight = static_cast<int>(bHeight * scale);
      }
    }

    FPDF_RenderPage(hDC, page, -marginLeft, -marginTop, bWidth, bHeight, 0,
                    FPDF_ANNOT | FPDF_PRINTING);
    FPDF_ClosePage(page);
    r = EndPage(hDC);
  }

  FPDF_CloseDocument(doc);
  FPDF_DestroyLibrary();

  EndDoc(hDC);

  DeleteDC(hDC);
  GlobalFree(hDevNames);
  ClosePrinter(hDevMode);

  printing->onCompleted(this, true, "");
}

void PrintJob::cancelJob(const std::string& error) {}

bool PrintJob::sharePdf(std::vector<uint8_t> data, const std::string& name) {
  TCHAR lpTempPathBuffer[MAX_PATH];

  auto ret = GetTempPath(MAX_PATH, lpTempPathBuffer);
  if (ret > MAX_PATH || (ret == 0)) {
    return false;
  }

  auto filename = fromUtf8(toUtf8(lpTempPathBuffer) + "\\" + name);

  auto output_file =
      std::basic_ofstream<uint8_t>{filename, std::ios::out | std::ios::binary};
  output_file.write(data.data(), data.size());
  output_file.close();

  SHELLEXECUTEINFO ShExecInfo;
  ShExecInfo.cbSize = sizeof(SHELLEXECUTEINFO);
  ShExecInfo.fMask = 0;
  ShExecInfo.hwnd = nullptr;
  ShExecInfo.lpVerb = TEXT("open");
  ShExecInfo.lpFile = filename.c_str();
  ShExecInfo.lpParameters = nullptr;
  ShExecInfo.lpDirectory = nullptr;
  ShExecInfo.nShow = SW_SHOWDEFAULT;
  ShExecInfo.hInstApp = nullptr;

  ret = ShellExecuteEx(&ShExecInfo);

  return ret == TRUE;
}

void PrintJob::pickPrinter(void* result) {}

void PrintJob::rasterPdf(std::vector<uint8_t> data,
                         std::vector<int> pages,
                         double scale) {
  FPDF_LIBRARY_CONFIG config;
  config.version = 2;
  config.m_pUserFontPaths = nullptr;
  config.m_pIsolate = nullptr;
  config.m_v8EmbedderSlot = 0;
  FPDF_InitLibraryWithConfig(&config);

  auto doc = FPDF_LoadMemDocument64(data.data(), data.size(), nullptr);
  if (!doc) {
    FPDF_DestroyLibrary();
    printing->onPageRasterEnd(this, "Cannot raster a malformed PDF file");
    return;
  }

  auto pageCount = FPDF_GetPageCount(doc);

  if (pages.size() == 0) {
    // Use all pages
    pages.resize(pageCount);
    std::iota(std::begin(pages), std::end(pages), 0);
  }

  for (auto n : pages) {
    if (n >= pageCount) {
      continue;
    }

    auto page = FPDF_LoadPage(doc, n);
    if (!page) {
      continue;
    }

    auto width = FPDF_GetPageWidth(page);
    auto height = FPDF_GetPageHeight(page);

    auto bWidth = static_cast<int>(width * scale);
    auto bHeight = static_cast<int>(height * scale);

    auto bitmap = FPDFBitmap_Create(bWidth, bHeight, 1);
    FPDFBitmap_FillRect(bitmap, 0, 0, bWidth, bHeight, 0x00ffffff);

    FPDF_RenderPageBitmap(bitmap, page, 0, 0, bWidth, bHeight, 0,
                          FPDF_ANNOT | FPDF_LCD_TEXT);

    uint8_t* p = static_cast<uint8_t*>(FPDFBitmap_GetBuffer(bitmap));
    auto stride = FPDFBitmap_GetStride(bitmap);
    size_t l = static_cast<size_t>(bHeight * stride);

    // BGRA to RGBA conversion
    for (auto y = 0; y < bHeight; y++) {
      auto offset = y * stride;
      for (auto x = 0; x < bWidth; x++) {
        auto t = p[offset];
        p[offset] = p[offset + 2];
        p[offset + 2] = t;
        offset += 4;
      }
    }

    printing->onPageRasterized(std::vector<uint8_t>{p, p + l}, bWidth, bHeight,
                               this);

    FPDFBitmap_Destroy(bitmap);
    FPDF_ClosePage(page);
  }

  FPDF_CloseDocument(doc);

  FPDF_DestroyLibrary();

  printing->onPageRasterEnd(this, "");
}

std::map<std::string, bool> PrintJob::printingInfo() {
  return std::map<std::string, bool>{
      {"directPrint", true},     {"dynamicLayout", true}, {"canPrint", true},
      {"canListPrinters", true}, {"canShare", true},      {"canRaster", true},
  };
}

}  // namespace nfet
