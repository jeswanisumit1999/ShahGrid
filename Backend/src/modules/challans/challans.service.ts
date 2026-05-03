import PDFDocument from 'pdfkit';
import { prisma } from '../../lib/prisma';
import { AppError } from '../../errors/AppError';

function fmtCurrency(amount: number) {
  return `Rs. ${Number(amount).toLocaleString('en-IN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

function fmtDate(iso: Date | string) {
  return new Date(iso).toLocaleDateString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  });
}

type DocType = InstanceType<typeof PDFDocument>;

interface PageItem {
  name: string;
  sku: string;
  quantity: number;
  unitPrice: number;
}

/** Draws the common header (title, order no, consignee, sales officer) and
 *  returns the Y position where content should start. */
function drawPageHeader(
  doc: DocType,
  opts: {
    shortId: string;
    orderDate: Date | string;
    retailerName: string;
    retailerPhone: string;
    retailerAddress: string | null;
    salesOfficerName: string;
    orderNotes: string | null;
  }
): void {
  const pageW = doc.page.width;
  const L = 50;
  const R = pageW - 50;
  const W = R - L;

  // Title
  doc.fontSize(20).font('Helvetica-Bold')
    .text('DELIVERY CHALLAN', L, 50, { width: W, align: 'center' });

  // Order No + Date
  const metaY = 88;
  doc.fontSize(9).font('Helvetica').text(`Order No: ${opts.shortId}`, L, metaY);
  doc.text(`Date: ${fmtDate(opts.orderDate)}`, L, metaY, { width: W, align: 'right' });

  // Two-column info block
  const infoY = metaY + 18;
  const leftColW = W * 0.55;
  const rightColX = L + W * 0.6;
  const rightColW = W * 0.4;

  let lY = infoY;
  doc.font('Helvetica-Bold').fontSize(9).text('Consignee (Ship To):', L, lY);
  lY += 13;
  doc.font('Helvetica').text(opts.retailerName, L, lY, { width: leftColW });
  lY += doc.heightOfString(opts.retailerName, { width: leftColW });
  doc.text(`Phone: ${opts.retailerPhone}`, L, lY, { width: leftColW });
  lY += 13;
  if (opts.retailerAddress) {
    doc.text(`Address: ${opts.retailerAddress}`, L, lY, { width: leftColW });
    lY += doc.heightOfString(`Address: ${opts.retailerAddress}`, { width: leftColW });
  }

  let rY = infoY;
  doc.font('Helvetica-Bold').text('Sales Officer:', rightColX, rY, { width: rightColW });
  rY += 13;
  doc.font('Helvetica').text(opts.salesOfficerName, rightColX, rY, { width: rightColW });
  rY += 13;

  doc.y = Math.max(lY, rY) + 10;

  // Divider
  doc.moveTo(L, doc.y).lineTo(R, doc.y).strokeColor('#aaaaaa').stroke().strokeColor('#000000');
  doc.y += 8;
}

/** Draws the items table and returns the total. */
function drawItemsTable(doc: DocType, items: PageItem[]): number {
  const pageW = doc.page.width;
  const L = 50;
  const R = pageW - 50;
  const W = R - L;

  const cProduct = L;
  const cSku     = L + W * 0.42;
  const cQty     = L + W * 0.62;
  const cPrice   = L + W * 0.74;
  const cAmount  = L + W * 0.87;
  const wProduct = cSku - cProduct - 4;
  const wSku     = cQty - cSku - 4;
  const wQty     = cPrice - cQty - 4;
  const wPrice   = cAmount - cPrice - 4;
  const wAmount  = R - cAmount;

  const thY = doc.y;
  doc.rect(L, thY - 3, W, 15).fill('#eeeeee').fillColor('#000000');
  doc.fontSize(8).font('Helvetica-Bold')
    .text('Product',    cProduct, thY, { width: wProduct })
    .text('SKU',        cSku,     thY, { width: wSku })
    .text('Qty',        cQty,     thY, { width: wQty })
    .text('Unit Price', cPrice,   thY, { width: wPrice })
    .text('Amount',     cAmount,  thY, { width: wAmount });
  doc.y = thY + 15;

  let total = 0;

  for (const item of items) {
    const lineAmt = item.quantity * item.unitPrice;
    total += lineAmt;

    const rowY = doc.y + 3;
    const rowH = Math.max(doc.heightOfString(item.name, { width: wProduct }), 13);

    doc.fontSize(8).font('Helvetica')
      .text(item.name,                   cProduct, rowY, { width: wProduct })
      .text(item.sku,                    cSku,     rowY, { width: wSku })
      .text(String(item.quantity),       cQty,     rowY, { width: wQty })
      .text(fmtCurrency(item.unitPrice), cPrice,   rowY, { width: wPrice })
      .text(fmtCurrency(lineAmt),        cAmount,  rowY, { width: wAmount });

    doc.y = rowY + rowH + 2;
    doc.moveTo(L, doc.y).lineTo(R, doc.y).strokeColor('#e0e0e0').stroke().strokeColor('#000000');
  }

  return total;
}

/** Draws notes (if any), signature block, and page footer. */
function drawPageFooter(
  doc: DocType,
  opts: { notes: string | null; pageLabel: string }
): void {
  const pageW = doc.page.width;
  const L = 50;
  const R = pageW - 50;
  const W = R - L;

  if (opts.notes) {
    doc.y += 10;
    doc.fontSize(8).font('Helvetica-Bold')
      .text('Notes: ', L, doc.y, { continued: true })
      .font('Helvetica').text(opts.notes, { width: W });
  }

  const sigTop = doc.page.height - 110;
  doc.y = sigTop;
  doc.moveTo(L, sigTop).lineTo(R, sigTop).strokeColor('#aaaaaa').stroke().strokeColor('#000000');

  const sigY = sigTop + 12;
  const sigColW = W / 2 - 20;
  const sigRX = L + W / 2 + 10;

  doc.fontSize(8).font('Helvetica').text('Delivered by:', L, sigY);
  doc.moveTo(L, sigY + 22).lineTo(L + sigColW, sigY + 22).stroke();
  doc.text('Name & Signature', L, sigY + 25, { width: sigColW });

  doc.text('Received by:', sigRX, sigY);
  doc.moveTo(sigRX, sigY + 22).lineTo(sigRX + sigColW, sigY + 22).stroke();
  doc.text('Name & Signature', sigRX, sigY + 25, { width: sigColW });

  doc.fontSize(7).fillColor('#888888')
    .text(
      `${opts.pageLabel}   —   Generated on ${fmtDate(new Date())}`,
      L,
      doc.page.height - 30,
      { width: W, align: 'center' }
    )
    .fillColor('#000000');
}

export async function generateChallanPdf(orderId: string): Promise<Buffer> {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: {
      retailer: true,
      salesOfficer: { select: { name: true } },
      orderItems: {
        include: { product: { select: { name: true, sku: true } } },
      },
      shipments: {
        include: {
          company: { select: { name: true } },
          shipmentItems: {
            include: {
              orderItem: {
                include: { product: { select: { name: true, sku: true } } },
              },
            },
          },
        },
        orderBy: { createdAt: 'asc' },
      },
    },
  });

  if (!order) throw AppError.notFound('Order');

  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 50, autoFirstPage: false });
    const chunks: Buffer[] = [];
    doc.on('data', (c: Buffer) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const shortId = order.id.split('-')[0].toUpperCase();
    const headerOpts = {
      shortId,
      orderDate: order.createdAt,
      retailerName: order.retailer.name,
      retailerPhone: order.retailer.phone,
      retailerAddress: order.retailer.address,
      salesOfficerName: order.salesOfficer.name,
      orderNotes: order.notes,
    };

    const L = 50;
    const R = 545; // A4 width (595pt) minus margin (50)
    const W = R - L;

    // ── Direct Sale: single page from order items ─────────────────────────────
    if (order.isDirectSale || order.shipments.length === 0) {
      doc.addPage();
      drawPageHeader(doc, headerOpts);

      doc.fontSize(11).font('Helvetica-Bold')
        .text('Direct Sale', L, doc.y, { width: W });
      doc.y += 14;

      const items: PageItem[] = order.orderItems.map((oi) => ({
        name: oi.product.name,
        sku: oi.product.sku,
        quantity: oi.quantity,
        unitPrice: Number(oi.unitPrice),
      }));

      const total = drawItemsTable(doc, items);

      doc.y += 6;
      doc.fontSize(9).font('Helvetica-Bold')
        .text(`Order Total: ${fmtCurrency(total)}`, L, doc.y, { width: W, align: 'right' });

      drawPageFooter(doc, { notes: order.notes, pageLabel: 'Page 1 of 1' });
      doc.end();
      return;
    }

    // ── Regular order: one page per shipment ──────────────────────────────────
    const totalShipments = order.shipments.length;

    for (let si = 0; si < totalShipments; si++) {
      const shipment = order.shipments[si];
      doc.addPage();
      drawPageHeader(doc, headerOpts);

      // Shipment section header
      const shipHeaderY = doc.y;
      doc.fontSize(11).font('Helvetica-Bold')
        .text(
          `Shipment ${si + 1} of ${totalShipments}  —  ${shipment.company.name}`,
          L, shipHeaderY, { width: W }
        );
      doc.y = shipHeaderY + 16;
      doc.fontSize(8).font('Helvetica')
        .text(
          `Status: ${shipment.status}   |   Shipment ID: ${shipment.id.split('-')[0].toUpperCase()}`,
          L, doc.y, { width: W }
        );
      doc.y += 14;

      const items: PageItem[] = shipment.shipmentItems.map((item) => ({
        name: item.orderItem.product.name,
        sku: item.orderItem.product.sku,
        quantity: item.quantity,
        unitPrice: Number(item.orderItem.unitPrice),
      }));

      const total = drawItemsTable(doc, items);

      doc.y += 6;
      doc.fontSize(9).font('Helvetica-Bold')
        .text(`Shipment Total: ${fmtCurrency(total)}`, L, doc.y, { width: W, align: 'right' });

      drawPageFooter(doc, {
        notes: order.notes,
        pageLabel: `Page ${si + 1} of ${totalShipments}`,
      });
    }

    doc.end();
  });
}
