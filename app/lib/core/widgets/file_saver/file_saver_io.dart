import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<void> saveOrShareFile(List<int> bytes, String fileName, String mimeType) async {
  final extension = fileName.contains('.') ? fileName.split('.').last : null;
  await FilePicker.platform.saveFile(
    dialogTitle: 'Save $fileName',
    fileName: fileName,
    bytes: Uint8List.fromList(bytes),
    type: extension == null ? FileType.any : FileType.custom,
    allowedExtensions: extension == null ? null : [extension],
  );
}
