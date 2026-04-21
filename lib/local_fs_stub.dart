import 'dart:typed_data';

Future<void> writeStringToPath(String path, String content) async {
  throw UnsupportedError('Nur mobil/Desktop; im Web wird Export per Teilen genutzt.');
}

Future<void> writeBytesToPath(String path, List<int> bytes) async {
  throw UnsupportedError('Nur mobil/Desktop; im Web wird Export per Teilen genutzt.');
}

Future<String> readStringFromPath(String path) async {
  throw UnsupportedError('Nur mobil/Desktop; im Web Dateiinhalt ueber Bytes.');
}

Future<Uint8List> readBytesFromPath(String path) async {
  throw UnsupportedError('Nur mobil/Desktop; im Web Dateiinhalt ueber Bytes.');
}
