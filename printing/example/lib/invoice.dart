// An invoice example in the style of common accounting-software exports:
// a bordered header (seller / consignee / buyer / invoice details) repeated
// on every page, an itemised table that can span any number of pages, and a
// totals + footer block (amount in words, bank details, declaration and
// signature) that is only ever drawn once, flush with the bottom of the
// LAST page.
//
// Three things make that possible, all provided by [pw.MultiPage]:
//
// 1. Automatic pagination: a [pw.Table] is a "spanning" widget, so when
//    passed straight to `build:` it is free to continue on to as many
//    pages as it needs, repeating any [pw.TableRow] created with
//    `repeat: true` (the column header row here) on every page.
//
// 2. Only-on-the-last-page content: everything placed in `build:` *after*
//    the items table (the blank filler, the totals row and the footer) is
//    only reached once the table has produced its very last row. On a page
//    where the table still has more rows to draw, none of that trailing
//    content is even looked at, so it can never appear on an intermediate
//    page - no `pageNumber == pagesCount` bookkeeping required.
//
// 3. Stretch-to-fit: [pw.Expanded] used as a direct child of `build:` is
//    given whatever vertical space is left over on whichever page it lands
//    on (page height, minus the header, minus everything else on that
//    page). Because the totals row and footer only get reached on the last
//    page, that's the only page this filler ever appears on - and it makes
//    the totals row land exactly at the page's bottom margin, however many
//    (or few) item rows preceded it.
//
// See main.dart, where `generateInvoice` below is wired up to a
// [PdfPreview] widget alongside the other demo.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared by [generateInvoice]'s [pw.MultiPage] and [_buildHeader], which
/// needs to know the page margins to measure the available header width.
const _pageMargin = pw.EdgeInsets.fromLTRB(28, 28, 28, 24);

/// Builds the invoice PDF.
///
/// [itemCount] sets how many line items to invent, which is what drives the
/// page count - roughly 30 rows fit on a page, so 7 stays on one page, 45
/// spills onto a second and 95 runs to a fourth (on A4 or Letter, with or
/// without the GST summary). However many pages that works out to, the
/// totals and footer stay pinned to the bottom of the last one, and the
/// header and page number repeat on every page.
///
/// Pass [showGstSummary] to add an HSN/SAC-wise tax breakup above the
/// declaration, and charge GST on top of the line items.
Future<Uint8List> generateInvoice(
  PdfPageFormat format, {
  int itemCount = 7,
  bool showGstSummary = false,
}) async {
  final invoice =
      _sampleInvoice(itemCount: itemCount, showGstSummary: showGstSummary);
  final pdf = pw.Document();
  final contentWidth = format.width - _pageMargin.left - _pageMargin.right;

  pdf.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: _pageMargin,
      header: (context) => _buildHeader(context, invoice, contentWidth),
      footer: _buildPageNumber,
      build: (context) => [
        _buildItemsTable(invoice),

        // See point 3 above: stretches to fill whatever is left of the
        // page the item table finished on.
        pw.Expanded(child: _boxSides(contentWidth)),

        _buildTotalsRow(invoice),
        _buildFooter(invoice),
      ],
    ),
  );

  return pdf.save();
}

// ---------------------------------------------------------------------------
// Header (repeated on every page)
// ---------------------------------------------------------------------------

const _sellerFlex = 11;
const _infoFlex = 9;

pw.Widget _buildHeader(
    pw.Context context, Invoice invoice, double contentWidth) {
  // The seller/consignee/buyer column is usually shorter than the invoice
  // details grid next to it. Measure the grid ahead of time so the other
  // column can be told to match its height - otherwise the divider between
  // the two stops short whenever one side has less text than the other.
  final infoColumn = _invoiceInfoColumn(invoice);
  infoColumn.layout(
    context,
    pw.BoxConstraints(
        maxWidth: contentWidth * _infoFlex / (_sellerFlex + _infoFlex)),
  );

  return pw.Container(
    // No bottom border here: the items table's own top border is what
    // closes this box off, so the title, the seller/buyer grid and the
    // table all read as one continuous rectangle rather than separate
    // boxes with gaps in between.
    decoration: const pw.BoxDecoration(
      border: pw.Border(
          left: pw.BorderSide(), top: pw.BorderSide(), right: pw.BorderSide()),
    ),
    child: pw.Column(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Column(
            children: [
              pw.Center(
                child: pw.Text(
                  context.pageNumber == 1 ? 'INVOICE' : 'INVOICE (contd.)',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'Credit Sales',
                  style: const pw.TextStyle(
                      fontSize: 9, decoration: pw.TextDecoration.underline),
                ),
              ),
            ],
          ),
        ),
        pw.Divider(height: 1, thickness: .75),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: _sellerFlex,
              child: _sellerColumn(invoice, minHeight: infoColumn.box!.height),
            ),
            pw.Expanded(flex: _infoFlex, child: infoColumn),
          ],
        ),
      ],
    ),
  );
}

/// "Page x of y", printed just below the invoice box on every page.
///
/// [pw.Context.pagesCount] is only final once the whole document has been
/// laid out - MultiPage's first pass genuinely cannot know it. It rebuilds
/// the footer during its second pass though, so the printed total ends up
/// correct. The fixed height is what makes that safe: the first pass has to
/// reserve exactly as much room as the second pass will use, and without it
/// a footer that is empty on pass one and a line of text on pass two would
/// let the last table row run underneath the page number.
pw.Widget _buildPageNumber(pw.Context context) {
  return pw.Container(
    height: 14,
    alignment: pw.Alignment.centerRight,
    child: pw.Text(
      // A lone page carries no useful "1 of 1" - drop the text, keep the
      // space, so single- and multi-page invoices lay out identically.
      context.pagesCount > 1
          ? 'Page ${context.pageNumber} of ${context.pagesCount}'
          : '',
      style: const pw.TextStyle(fontSize: 8),
    ),
  );
}

pw.Widget _sellerColumn(Invoice invoice, {required double minHeight}) {
  pw.Widget block(String? label, String title, String body) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (label != null)
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
          pw.Text(title,
              style:
                  pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text(body, style: const pw.TextStyle(fontSize: 8.5)),
        ],
      ),
    );
  }

  return pw.Container(
    constraints: pw.BoxConstraints(minHeight: minHeight),
    decoration: const pw.BoxDecoration(
      border: pw.Border(right: pw.BorderSide(width: .75)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        block(null, invoice.sellerName, invoice.sellerAddress),
        pw.Divider(height: 1, thickness: .5),
        block('Consignee (Ship to)', invoice.consigneeName,
            invoice.consigneeAddress),
        pw.Divider(height: 1, thickness: .5),
        block('Buyer (Bill to)', invoice.buyerName, invoice.buyerAddress),
      ],
    ),
  );
}

pw.Widget _invoiceInfoColumn(Invoice invoice) {
  pw.Widget gridCell(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style:
                  pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 2),
          pw.Text(value.isEmpty ? ' ' : value,
              style: const pw.TextStyle(fontSize: 8.5)),
        ],
      ),
    );
  }

  pw.Widget gridRow(String l1, String v1, String l2, String v2) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: gridCell(l1, v1)),
        pw.Expanded(child: gridCell(l2, v2)),
      ],
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      gridRow('Invoice No.', invoice.invoiceNumber, 'Dated',
          _fmtDate(invoice.invoiceDate)),
      pw.Divider(height: 1, thickness: .5),
      gridRow('Delivery Note', invoice.deliveryNote, 'Mode/Terms of Payment',
          invoice.modeOfPayment),
      pw.Divider(height: 1, thickness: .5),
      gridRow('Reference No. & Date', invoice.referenceNo, 'Other References',
          invoice.otherReferences),
      pw.Divider(height: 1, thickness: .5),
      gridRow("Buyer's Order No.", invoice.buyersOrderNo, 'Dated',
          invoice.buyersOrderDate),
      pw.Divider(height: 1, thickness: .5),
      gridRow('Dispatch Doc No.', invoice.dispatchDocNo, 'Delivery Note Date',
          invoice.deliveryNoteDate),
      pw.Divider(height: 1, thickness: .5),
      gridRow('Dispatched through', invoice.dispatchedThrough, 'Destination',
          invoice.destination),
      pw.Divider(height: 1, thickness: .5),
      gridCell('Terms of Delivery', invoice.termsOfDelivery),
    ],
  );
}

// ---------------------------------------------------------------------------
// Items table (spans pages automatically; header row repeats on every page)
// ---------------------------------------------------------------------------

/// Relative widths of Sl No. / Description / Quantity / Rate / per / Amount.
/// Shared by the items table, the totals row and the blank filler's column
/// dividers so all three line up exactly.
const _columnWeights = [0.6, 4.4, 1.1, 1.0, 0.7, 1.4];

/// Shared by the table's own `verticalInside` and the filler's divider
/// rectangles in [_boxSides], so both are centered on the same line.
const _dividerWidth = 0.75;

final Map<int, pw.TableColumnWidth> _itemColumnWidths = {
  for (var i = 0; i < _columnWeights.length; i++)
    i: pw.FlexColumnWidth(_columnWeights[i]),
};

pw.Widget _cell(
  String text, {
  pw.TextStyle? style,
  pw.Alignment align = pw.Alignment.centerLeft,
}) {
  return pw.Container(
    alignment: align,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Text(text, style: style ?? const pw.TextStyle(fontSize: 9)),
  );
}

pw.Widget _buildItemsTable(Invoice invoice) {
  final headerStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);

  return pw.Table(
    columnWidths: _itemColumnWidths,
    border: const pw.TableBorder(
      left: pw.BorderSide(),
      top: pw.BorderSide(),
      right: pw.BorderSide(),
      bottom: pw.BorderSide(),
      // Thicker than a hairline (matched by _boxSides's dividers below) so
      // that a sub-point rendering seam between the table's own dividers
      // and the filler's - some PDF viewers snap two independently-stroked
      // lines at the same coordinate to different device pixels when
      // heavily zoomed in - stays visually negligible.
      verticalInside: pw.BorderSide(width: _dividerWidth),
      // No horizontalInside: this invoice only rules off columns, not
      // individual rows. The bottom border closes the box wherever the
      // table's content actually ends on any page it doesn't finish on -
      // no gap, because it's the table's own edge, not a line positioned
      // separately. On the page it *does* finish on, _boxSides paints over
      // this one bottom border with white, so the column dividers still
      // read as running straight into the blank filler underneath.
    ),
    children: [
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _cell('Sl\nNo.', style: headerStyle, align: pw.Alignment.center),
          _cell('Description of Goods', style: headerStyle),
          _cell('Quantity', style: headerStyle, align: pw.Alignment.center),
          _cell('Rate', style: headerStyle, align: pw.Alignment.centerRight),
          _cell('per', style: headerStyle, align: pw.Alignment.center),
          _cell('Amount', style: headerStyle, align: pw.Alignment.centerRight),
        ],
      ),
      for (var i = 0; i < invoice.items.length; i++)
        pw.TableRow(children: [
          _cell('${i + 1}', align: pw.Alignment.center),
          _cell(invoice.items[i].description),
          _cell(_fmtQty(invoice.items[i].quantity), align: pw.Alignment.center),
          _cell(_fmtAmount(invoice.items[i].rate),
              align: pw.Alignment.centerRight),
          _cell(invoice.items[i].unit, align: pw.Alignment.center),
          _cell(_fmtAmount(invoice.items[i].amount),
              align: pw.Alignment.centerRight),
        ]),
    ],
  );
}

/// Blank filler: draws the box's left/right sides plus one thin vertical
/// rule per column boundary, so every column divider in the items table
/// reads as continuing straight down into the totals row, however tall the
/// free space on the last page turns out to be.
///
/// This has to be a [pw.Stack] of absolutely-[pw.Positioned] lines rather
/// than (say) a [pw.Row] of bordered, stretched cells: the enclosing
/// [pw.Expanded] is measured once with an unbounded height before MultiPage
/// knows how much space is actually left on the page, and a stretched Row
/// would try to give its cells that same unbounded height and crash. A
/// `Stack` only takes on the real (bounded) height once [pw.Expanded]
/// assigns it - its plain, undecorated first child is what keeps it at
/// height zero until then.
pw.Widget _boxSides(double contentWidth) {
  final totalWeight = _columnWeights.reduce((a, b) => a + b);
  final dividerXs = <double>[];
  var cumulativeWeight = 0.0;
  for (var i = 0; i < _columnWeights.length - 1; i++) {
    cumulativeWeight += _columnWeights[i];
    dividerXs.add(contentWidth * cumulativeWeight / totalWeight);
  }

  // Every line below is drawn 1pt *above* this widget's own top edge so it
  // overlaps the items table's lines rather than merely meeting them end to
  // end - two independently stroked lines at the same coordinate can land a
  // device pixel apart once rasterized. `Overflow.visible` is what allows
  // that (a Stack clips its children to its own box by default).
  //
  // Paint order matters and is the whole trick here: the white eraser goes
  // down FIRST, then every line is re-drawn on top of it. Erasing after
  // drawing would punch a notch straight back out of the box's own edges.
  return pw.Stack(
    overflow: pw.Overflow.visible,
    children: [
      // Sizing child only - an empty box that takes on whatever height
      // Expanded hands down. Everything after it is positioned against it.
      pw.Container(),

      // This filler is only ever reached on the page where the items table
      // finishes, directly below that table's bottom border. Erase that one
      // border so the column dividers read as a continuous run from the
      // table down into this blank space. Overhangs sideways to also catch
      // the border's end caps.
      pw.Positioned(
        left: -1,
        right: -1,
        top: -1,
        child: pw.Container(height: 2.5, color: PdfColors.white),
      ),

      // The box's left and right edges, re-drawn over the erased strip.
      pw.Positioned(
        left: 0,
        right: 0,
        top: -1,
        bottom: 0,
        child: pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(left: pw.BorderSide(), right: pw.BorderSide()),
          ),
        ),
      ),

      // The column dividers. A stroked line (what the table itself uses) is
      // centered on its path, but a Positioned rectangle is placed by its
      // left edge - hence the half-width shift, so both end up centered on
      // the same line instead of sitting a few tenths of a point apart.
      for (final x in dividerXs)
        pw.Positioned(
          left: x - _dividerWidth / 2,
          top: -1,
          bottom: 0,
          child: pw.Container(width: _dividerWidth, color: PdfColors.black),
        ),
    ],
  );
}

pw.Widget _buildTotalsRow(Invoice invoice) {
  final style = pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold);

  pw.Widget totalCell(String text,
      {pw.Alignment align = pw.Alignment.centerLeft}) {
    return pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(text, style: style),
    );
  }

  return pw.Table(
    columnWidths: _itemColumnWidths,
    border: const pw.TableBorder(
      left: pw.BorderSide(),
      right: pw.BorderSide(),
      top: pw.BorderSide(),
      bottom: pw.BorderSide(),
      verticalInside: pw.BorderSide(width: _dividerWidth),
    ),
    children: [
      pw.TableRow(children: [
        totalCell(''),
        totalCell('Total'),
        totalCell('${_fmtQty(invoice.totalQuantity)} pcs',
            align: pw.Alignment.center),
        totalCell(''),
        totalCell(''),
        totalCell(_fmtAmount(invoice.grandTotal),
            align: pw.Alignment.centerRight),
      ]),
    ],
  );
}

// ---------------------------------------------------------------------------
// GST summary (optional - see Invoice.showGstSummary)
// ---------------------------------------------------------------------------

/// The HSN/SAC-wise tax breakup, as a block that continues the invoice's
/// bordered box downward the same way the rest of the footer does.
pw.Widget _buildGstBlock(Invoice invoice) {
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(4, 0, 4, 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(left: pw.BorderSide(), right: pw.BorderSide()),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildGstSummaryTable(invoice),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Tax Amount (in words) : ',
                style:
                    pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
            pw.Text('INR ${_amountInWords(invoice.taxTotal)} Only',
                style:
                    pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _buildGstSummaryTable(Invoice invoice) {
  final labelStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
  final boldStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
  const dataStyle = pw.TextStyle(fontSize: 8);

  pw.Widget txt(String text, pw.TextStyle style, pw.Alignment align) {
    return pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: pw.Text(text, style: style),
    );
  }

  // "Central Tax" and "State Tax" each span a Rate and an Amount column.
  // The pdf package's Table has no colspan, so those two live in a nested
  // one-row table inside a single outer column: that way the sub-divider
  // sits at the same fraction of the column width in the header and in
  // every data row, and the two line up without any manual arithmetic.
  pw.Widget pair(
    String rate,
    String amount,
    pw.TextStyle style, {
    bool topBorder = false,
  }) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1.7),
      },
      border: pw.TableBorder(
        top: topBorder
            ? const pw.BorderSide(width: _dividerWidth)
            : pw.BorderSide.none,
        verticalInside: const pw.BorderSide(width: _dividerWidth),
      ),
      children: [
        pw.TableRow(children: [
          txt(rate, style, pw.Alignment.center),
          txt(amount, style, pw.Alignment.centerRight),
        ]),
      ],
    );
  }

  pw.Widget groupHeader(String label) {
    return pw.Column(children: [
      txt(label, labelStyle, pw.Alignment.center),
      pair('Rate', 'Amount', labelStyle, topBorder: true),
    ]);
  }

  final halfTaxTotal = invoice.taxTotal / 2;

  return pw.Table(
    columnWidths: const {
      0: pw.FlexColumnWidth(2.4), // HSN/SAC
      1: pw.FlexColumnWidth(1.4), // Taxable Value
      2: pw.FlexColumnWidth(1.7), // Central Tax (Rate + Amount)
      3: pw.FlexColumnWidth(1.7), // State Tax (Rate + Amount)
      4: pw.FlexColumnWidth(1.3), // Total Tax Amount
    },
    border: pw.TableBorder(
      left: const pw.BorderSide(width: _dividerWidth),
      right: const pw.BorderSide(width: _dividerWidth),
      top: const pw.BorderSide(width: _dividerWidth),
      bottom: const pw.BorderSide(width: _dividerWidth),
      horizontalInside: const pw.BorderSide(width: _dividerWidth),
      verticalInside: const pw.BorderSide(width: _dividerWidth),
    ),
    children: [
      pw.TableRow(
        // Stretches the single-line cells to the height of the two-line
        // grouped ones, so their labels centre against the whole header.
        verticalAlignment: pw.TableCellVerticalAlignment.full,
        children: [
          txt('HSN/SAC', labelStyle, pw.Alignment.center),
          txt('Taxable\nValue', labelStyle, pw.Alignment.center),
          groupHeader('Central Tax'),
          groupHeader('State Tax'),
          txt('Total\nTax Amount', labelStyle, pw.Alignment.center),
        ],
      ),
      for (final line in invoice.gstSummary)
        pw.TableRow(children: [
          txt(line.hsn, dataStyle, pw.Alignment.centerLeft),
          txt(_fmtAmount(line.taxableValue), dataStyle,
              pw.Alignment.centerRight),
          pair('${_fmtQty(line.halfRate)}%', _fmtAmount(line.halfTax),
              dataStyle),
          pair('${_fmtQty(line.halfRate)}%', _fmtAmount(line.halfTax),
              dataStyle),
          txt(_fmtAmount(line.totalTax), dataStyle, pw.Alignment.centerRight),
        ]),
      pw.TableRow(children: [
        txt('Total', boldStyle, pw.Alignment.centerRight),
        txt(_fmtAmount(invoice.grandTotal), boldStyle,
            pw.Alignment.centerRight),
        pair('', _fmtAmount(halfTaxTotal), boldStyle),
        pair('', _fmtAmount(halfTaxTotal), boldStyle),
        txt(_fmtAmount(invoice.taxTotal), boldStyle, pw.Alignment.centerRight),
      ]),
    ],
  );
}

// ---------------------------------------------------------------------------
// Footer (only ever reached, and only ever painted, on the last page)
// ---------------------------------------------------------------------------

pw.Widget _buildFooter(Invoice invoice) {
  // Wrapped in a Stack purely to keep the footer in one piece. A Column is
  // a spanning widget, so MultiPage is free to tear it across a page break
  // - which it does whenever the last page is tight (a Letter-height page
  // with a GST summary, say), stranding the declaration on a page of its
  // own and leaving the page above it with an unclosed box. Stack extends
  // MultiChildWidget, which is *not* a SpanningWidget, so the whole footer
  // moves to the next page intact instead of splitting. Note that wrapping
  // in a Container or Padding would not work: both delegate `canSpan`
  // straight through to their child.
  return pw.Stack(children: [
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Continues the totals row's box down to the declaration/bank
        // details block below, which is the one that actually closes it off
        // - so this whole section (items table through the signature block)
        // reads as a single bordered box.
        //
        // The top border normally lands exactly on the totals row's own
        // bottom border and is invisible against it. It earns its keep when
        // the footer gets bumped to a page of its own (see the Stack above):
        // there the header sits directly on top of this block, and since the
        // header deliberately has no bottom border of its own, this is the
        // only thing closing the header's box off.
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
                left: pw.BorderSide(),
                top: pw.BorderSide(),
                right: pw.BorderSide()),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Amount Chargeable (in words)',
                        style: pw.TextStyle(
                            fontSize: 8, fontStyle: pw.FontStyle.italic)),
                    pw.Text(
                      'INR ${_amountInWords(invoice.amountChargeable)} Only',
                      style: pw.TextStyle(
                          fontSize: 10, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
              pw.Text('E. & O.E',
                  style: pw.TextStyle(
                      fontSize: 8, fontStyle: pw.FontStyle.italic)),
            ],
          ),
        ),
        if (invoice.showGstSummary) _buildGstBlock(invoice),
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
                left: pw.BorderSide(),
                top: pw.BorderSide(),
                right: pw.BorderSide(),
                bottom: pw.BorderSide()),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 2,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Declaration',
                        style: const pw.TextStyle(
                            fontSize: 8,
                            decoration: pw.TextDecoration.underline)),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'We declare that this invoice shows the actual price '
                      'of the goods described and that all particulars are '
                      'true and correct.',
                      style: const pw.TextStyle(fontSize: 7.5),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("Company's Bank Details",
                        style: pw.TextStyle(
                            fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 3),
                    pw.Text('Bank Name      : ${invoice.bankName}',
                        style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('A/c No.        : ${invoice.accountNo}',
                        style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Branch & IFSC  : ${invoice.branchIfsc}',
                        style: const pw.TextStyle(fontSize: 8)),
                    pw.SizedBox(height: 18),
                    pw.Text('for ${invoice.sellerName}',
                        style: pw.TextStyle(
                            fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 18),
                    pw.Text('Authorised Signatory',
                        style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  ]);
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A single line item on the invoice.
class InvoiceItem {
  const InvoiceItem(
    this.description,
    this.quantity,
    this.unit,
    this.rate, {
    this.hsn = '',
    this.gstRate = 0,
  });

  /// What was sold.
  final String description;

  /// How many units of it.
  final num quantity;

  /// The unit the quantity is expressed in ('pcs', 'box', ...).
  final String unit;

  /// Price per unit.
  final double rate;

  /// HSN/SAC code this item is classified under. Only used by the GST
  /// summary, which groups its rows by (hsn, gstRate).
  final String hsn;

  /// Total GST percentage for this item, split evenly between central and
  /// state tax by the GST summary (18 means 9% CGST + 9% SGST).
  final double gstRate;

  /// [quantity] * [rate] - the taxable value, before any GST.
  double get amount => quantity * rate;

  /// GST payable on [amount].
  double get taxAmount => amount * gstRate / 100;
}

/// All the data needed to render the invoice.
class Invoice {
  Invoice({
    required this.sellerName,
    required this.sellerAddress,
    required this.consigneeName,
    required this.consigneeAddress,
    required this.buyerName,
    required this.buyerAddress,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.items,
    this.deliveryNote = '',
    this.modeOfPayment = '',
    this.referenceNo = '',
    this.otherReferences = '',
    this.buyersOrderNo = '',
    this.buyersOrderDate = '',
    this.dispatchDocNo = '',
    this.deliveryNoteDate = '',
    this.dispatchedThrough = '',
    this.destination = '',
    this.termsOfDelivery = '',
    this.bankName = '',
    this.accountNo = '',
    this.branchIfsc = '',
    this.showGstSummary = false,
  });

  /// When true, an HSN/SAC-wise tax breakup is printed below the
  /// amount-in-words line, and the amount chargeable includes GST. When
  /// false the invoice is tax-free and no summary is printed at all.
  final bool showGstSummary;

  final String sellerName;
  final String sellerAddress;
  final String consigneeName;
  final String consigneeAddress;
  final String buyerName;
  final String buyerAddress;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final List<InvoiceItem> items;
  final String deliveryNote;
  final String modeOfPayment;
  final String referenceNo;
  final String otherReferences;
  final String buyersOrderNo;
  final String buyersOrderDate;
  final String dispatchDocNo;
  final String deliveryNoteDate;
  final String dispatchedThrough;
  final String destination;
  final String termsOfDelivery;
  final String bankName;
  final String accountNo;
  final String branchIfsc;

  /// Sum of every item's quantity.
  num get totalQuantity =>
      items.fold<num>(0, (sum, item) => sum + item.quantity);

  /// Sum of every item's amount - the total taxable value, before GST.
  double get grandTotal =>
      items.fold<double>(0, (sum, item) => sum + item.amount);

  /// Total GST across every item, or zero when [showGstSummary] is off.
  double get taxTotal => showGstSummary
      ? items.fold<double>(0, (sum, item) => sum + item.taxAmount)
      : 0;

  /// What the buyer actually owes: taxable value plus any GST.
  double get amountChargeable => grandTotal + taxTotal;

  /// The GST summary's rows: one per distinct (HSN/SAC, rate) pair, in the
  /// order those pairs first appear in [items].
  List<GstSummaryLine> get gstSummary {
    final lines = <String, GstSummaryLine>{};
    for (final item in items) {
      final key = '${item.hsn}@${item.gstRate}';
      final line = lines[key] ??= GstSummaryLine(item.hsn, item.gstRate);
      line.taxableValue += item.amount;
    }
    return lines.values.toList();
  }
}

/// One row of the HSN/SAC-wise tax breakup.
class GstSummaryLine {
  GstSummaryLine(this.hsn, this.gstRate);

  /// The HSN/SAC code these items share.
  final String hsn;

  /// Their combined GST percentage, split evenly into central and state tax.
  final double gstRate;

  /// Combined pre-tax value of every item rolled up into this row.
  double taxableValue = 0;

  /// Half the GST rate - central and state tax are charged at this each.
  double get halfRate => gstRate / 2;

  /// Central tax payable, and the identical state tax figure.
  double get halfTax => taxableValue * halfRate / 100;

  /// Central plus state tax.
  double get totalTax => halfTax * 2;
}

Invoice _sampleInvoice({
  required int itemCount,
  required bool showGstSummary,
}) {
  // The HSN codes and rates are only consulted when showGstSummary is on:
  // biscuits are 1905 at 18%, the boxed assortments 2106 at 12%, so the
  // summary has more than one row to group.
  const baseItems = [
    InvoiceItem('Almond Cookies', 15, 'pcs', 30, hsn: '1905', gstRate: 18),
    InvoiceItem('Chocolate Chip Cookie', 15, 'pcs', 35,
        hsn: '1905', gstRate: 18),
    InvoiceItem('Oatmeal Cookies', 15, 'pcs', 40, hsn: '1905', gstRate: 18),
    InvoiceItem('Shortbread Cookies', 15, 'pcs', 60, hsn: '1905', gstRate: 18),
    InvoiceItem('Peanut Butter Cookies', 15, 'pcs', 55,
        hsn: '1905', gstRate: 18),
    InvoiceItem('Spritz Cookies', 5, 'box', 500, hsn: '2106', gstRate: 12),
    InvoiceItem('Butter Cookies', 5, 'box', 400, hsn: '2106', gstRate: 12),
  ];

  // Cycle through the seven sample products until there are itemCount
  // lines. A handful fit comfortably on one page; ask for enough and the
  // table simply runs on to a second, third, fourth ... page, with
  // MultiPage doing the pagination.
  final items = List<InvoiceItem>.generate(
      itemCount, (i) => baseItems[i % baseItems.length]);

  return Invoice(
    sellerName: 'National Enterprises',
    sellerAddress: 'Kadugodi',
    consigneeName: 'Ganeshji Enterprise',
    consigneeAddress: '',
    buyerName: 'Ganeshji Enterprise',
    buyerAddress: '',
    invoiceNumber: '4',
    invoiceDate: DateTime(2022, 10, 17),
    referenceNo: '4 dt. 17-Oct-22',
    bankName: 'Kotak Bank',
    accountNo: '2912515894',
    branchIfsc: 'M.G.Road & KKBK0008066',
    items: items,
    showGstSummary: showGstSummary,
  );
}

// ---------------------------------------------------------------------------
// Formatting helpers
//
// These are deliberately dependency-free (no `intl`) so the example only
// relies on `pdf`/`printing`. The core PDF fonts used here (no custom font
// is loaded) don't cover the ₹ glyph, hence "INR" instead of the rupee sign
// - load a Unicode font (e.g. via `PdfGoogleFonts` from this same package)
// if you need it.
// ---------------------------------------------------------------------------

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day.toString().padLeft(2, '0')}-${months[d.month - 1]}-${d.year}';
}

String _fmtQty(num value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

String _fmtAmount(num value) {
  final fixed = value.toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final wholePart = fixed.substring(0, dot);
  final decimalPart = fixed.substring(dot);
  final negative = wholePart.startsWith('-');
  final digits = negative ? wholePart.substring(1) : wholePart;

  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}$buffer$decimalPart';
}

const _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', //
  'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
  'Seventeen', 'Eighteen', 'Nineteen',
];
const _tens = [
  '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', //
  'Ninety',
];
const _scales = ['', 'Thousand', 'Million', 'Billion'];

String _threeDigitsToWords(int n) {
  final parts = <String>[];
  if (n >= 100) {
    parts.add('${_ones[n ~/ 100]} Hundred');
    n %= 100;
  }
  if (n >= 20) {
    final tensWord = _tens[n ~/ 10];
    final rem = n % 10;
    parts.add(rem > 0 ? '$tensWord ${_ones[rem]}' : tensWord);
  } else if (n > 0) {
    parts.add(_ones[n]);
  }
  return parts.join(' ');
}

/// A simplified (non-lakh/crore) number-to-words converter, good enough to
/// spell out typical invoice totals.
String _amountInWords(double amount) {
  var n = amount.floor();
  if (n == 0) {
    return 'Zero';
  }

  final groups = <int>[];
  while (n > 0) {
    groups.add(n % 1000);
    n ~/= 1000;
  }

  final parts = <String>[];
  for (var i = groups.length - 1; i >= 0; i--) {
    if (groups[i] == 0) {
      continue;
    }
    final words = _threeDigitsToWords(groups[i]);
    parts.add(_scales[i].isEmpty ? words : '$words ${_scales[i]}');
  }
  return parts.join(' ');
}
