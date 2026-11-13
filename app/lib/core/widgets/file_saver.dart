/// Saves a downloaded file (e.g. an invoice PDF or a passenger list).
/// Phones: the user picks where to save it. Web: the browser downloads it.
export 'file_saver/file_saver_io.dart' if (dart.library.js_interop) 'file_saver/file_saver_web.dart';
