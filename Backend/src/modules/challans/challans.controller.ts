import { Request, Response, NextFunction } from 'express';
import { generateChallanPdf } from './challans.service';

export async function getChallan(req: Request, res: Response, next: NextFunction) {
  try {
    const { id } = req.params;
    const pdf = await generateChallanPdf(id);
    const shortId = id.split('-')[0].toUpperCase();

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="challan_${shortId}.pdf"`);
    res.setHeader('Content-Length', pdf.length);
    res.send(pdf);
  } catch (err) {
    next(err);
  }
}
