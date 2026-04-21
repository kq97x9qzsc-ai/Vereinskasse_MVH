import 'dart:typed_data';

import 'local_fs_impl.dart' if (dart.library.html) 'local_fs_stub.dart' as impl;

Future<void> writeStringToPath(String path, String content) =>
    impl.writeStringToPath(path, content);

Future<void> writeBytesToPath(String path, List<int> bytes) =>
    impl.writeBytesToPath(path, bytes);

Future<String> readStringFromPath(String path) => impl.readStringFromPath(path);

Future<Uint8List> readBytesFromPath(String path) => impl.readBytesFromPath(path);
