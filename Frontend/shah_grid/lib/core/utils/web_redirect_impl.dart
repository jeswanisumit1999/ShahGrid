import 'package:web/web.dart';

/// Navigates the browser tab to [url] (same-window redirect).
void redirectToUrl(String url) => window.location.assign(url);
