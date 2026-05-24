import 'dart:typed_data';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;

class PdfPreviewHandle {
  PdfPreviewHandle._(this.blobUrl, this.viewType);
  final String blobUrl;
  final String viewType;

  void download(String filename) {
    final a = web.document.createElement('a') as web.HTMLAnchorElement;
    a.href = blobUrl;
    a.download = filename;
    web.document.body!.appendChild(a);
    a.click();
    a.remove();
  }

  void print() {
    // Open in a new tab — the browser's native PDF viewer has a print button.
    web.window.open(blobUrl, '_blank');
  }

  void dispose() {
    web.URL.revokeObjectURL(blobUrl);
  }
}

PdfPreviewHandle createPdfPreview(Uint8List bytes) {
  final viewType = 'pdf-iframe-${DateTime.now().microsecondsSinceEpoch}';
  final blob = web.Blob(
    [bytes.buffer.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);

  ui_web.platformViewRegistry.registerViewFactory(viewType, (_) {
    final iframe =
        web.document.createElement('iframe') as web.HTMLIFrameElement;
    iframe.src = url;
    iframe.style.cssText = 'width:100%;height:100%;border:none;';
    return iframe;
  });

  return PdfPreviewHandle._(url, viewType);
}
