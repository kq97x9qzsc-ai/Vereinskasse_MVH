import 'dart:io';

import 'package:excel/excel.dart';

void main(List<String> args) {
  final targetPath = args.isNotEmpty
      ? args.first
      : 'catalog${Platform.pathSeparator}Fruehlingsfest2026.xlsx';
  final file = File(targetPath);
  if (!file.existsSync()) {
    stderr.writeln('Datei nicht gefunden: ${file.path}');
    exitCode = 1;
    return;
  }

  final bytes = file.readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables['Einstellungen'];
  if (sheet == null) {
    stderr.writeln('Sheet "Einstellungen" nicht gefunden.');
    exitCode = 1;
    return;
  }

  var rowIndex = -1;
  for (var r = 2; r < sheet.maxRows; r++) {
    final key = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
        .value
        ?.toString()
        .trim();
    if (key == 'articleTileGap') {
      rowIndex = r;
      break;
    }
  }
  if (rowIndex < 0) {
    rowIndex = sheet.maxRows;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
        .value = TextCellValue('articleTileGap');
  }
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
      .value = TextCellValue('8');

  final out = excel.save();
  if (out == null) {
    stderr.writeln('Speichern fehlgeschlagen.');
    exitCode = 1;
    return;
  }
  file.writeAsBytesSync(out, flush: true);
  stdout.writeln('Aktualisiert: ${file.path}');
}
