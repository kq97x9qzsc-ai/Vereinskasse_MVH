import 'dart:io';
import 'dart:typed_data';

Future<void> writeStringToPath(String path, String content) async {
  await File(path).writeAsString(content);
}

Future<void> writeBytesToPath(String path, List<int> bytes) async {
  await File(path).writeAsBytes(bytes);
}

Future<String> readStringFromPath(String path) async {
  return File(path).readAsString();
}

Future<Uint8List> readBytesFromPath(String path) async {
  return File(path).readAsBytes();
}
