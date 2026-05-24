import 'dart:typed_data';

class PdfPreviewHandle {
  PdfPreviewHandle._();
  final String blobUrl = '';
  final String viewType = '';
  void download(String filename) {}
  void print() {}
  void dispose() {}
}

PdfPreviewHandle createPdfPreview(Uint8List bytes) => PdfPreviewHandle._();
