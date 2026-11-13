import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> saveOrShareFile(List<int> bytes, String fileName, String mimeType) async {
  final data = Uint8List.fromList(bytes).toJS;
  final blob = web.Blob(<web.BlobPart>[data].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
