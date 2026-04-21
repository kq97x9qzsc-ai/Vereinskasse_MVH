import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

void configureSqfliteForWeb() {
  databaseFactory = databaseFactoryFfiWeb;
}
