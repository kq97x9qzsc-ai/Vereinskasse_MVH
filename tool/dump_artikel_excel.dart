import 'dart:io';

import 'package:excel/excel.dart';

void main() {
  const path = r'c:\Users\frank\Desktop\Kasse Frühlingsfest\ArtikelApp.xlsx';
  final bytes = File(path).readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  for (final name in excel.tables.keys) {
    final sheet = excel.tables[name]!;
    print('=== $name rows=${sheet.maxRows} cols=${sheet.maxColumns} ===');
    for (var r = 0; r < sheet.maxRows; r++) {
      final row = <String>[];
      for (var c = 0; c < sheet.maxColumns; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        row.add(cell.value?.toString() ?? '');
      }
      print('$r\t${row.join(' | ')}');
    }
  }
}
