// dart run tool/generate_fruehlingsfest_seed.dart
// Schreibt lib/fruehlingsfest_artikel_seed.dart (UTF-8). Pfad zur xlsx unten anpassen.
import 'dart:io';

import 'package:excel/excel.dart';

bool cellHasX(Object? v) {
  final s = v?.toString().trim().toLowerCase() ?? '';
  return s == 'x' || s == '✓' || s == '1' || s == 'true';
}

double parsePrice(Object? v) {
  if (v == null) {
    return 0;
  }
  if (v is num) {
    return v.toDouble();
  }
  final s = v.toString().trim().replaceAll(',', '.');
  if (s.isEmpty) {
    return 0;
  }
  return double.tryParse(s) ?? 0;
}

int parseGroup(Object? v) {
  if (v is int) {
    return v;
  }
  if (v is double) {
    return v.round();
  }
  return int.tryParse(v?.toString().trim() ?? '') ?? 1;
}

void main() {
  const path = r'c:\Users\frank\Desktop\Kasse Frühlingsfest\ArtikelApp.xlsx';
  final outPath = '${Directory.current.path}${Platform.pathSeparator}lib${Platform.pathSeparator}fruehlingsfest_artikel_seed.dart';
  final bytes = File(path).readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables['Artikel'] ?? excel.tables.values.first;

  final buf = StringBuffer();
  buf.writeln('// Quelle: ArtikelApp.xlsx (tool/generate_fruehlingsfest_seed.dart). Reihenfolge = Excel-Zeilen.');
  buf.writeln(
    '// Spalten: Name, Preis, Gruppe 1/2, Mo–So (x=aktiv). Alt: nur Mi,Do,Fr,So ab Spalte D. Neu: Mo,Di leer dann Mi..So.',
  );
  buf.writeln('// Nach manueller Excel-Aenderung: Generator laufen lassen und kArticleCatalogSeedVersion erhoehen.');
  buf.writeln('');
  buf.writeln(
    'const List<(String name, double price, int groupExcelId, bool mi, bool donnerstag, bool freitag, bool sonntag)> kFruehlingsfestArtikelSeed = [',
  );

  String header(int c) =>
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).value?.toString().trim().toLowerCase() ?? '';
  final legacyWeekdays = header(3) == 'mi';
  final cMi = legacyWeekdays ? 3 : 5;
  final cDo = legacyWeekdays ? 4 : 6;
  final cFr = legacyWeekdays ? 5 : 7;
  final cSo = legacyWeekdays ? 6 : 9;

  for (var r = 1; r < sheet.maxRows; r++) {
    String cell(int c) =>
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value?.toString() ?? '';
    final name = cell(0).trim();
    if (name.isEmpty) {
      continue;
    }
    final price = parsePrice(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value);
    final group = parseGroup(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value);
    final mi = cellHasX(sheet.cell(CellIndex.indexByColumnRow(columnIndex: cMi, rowIndex: r)).value);
    final d = cellHasX(sheet.cell(CellIndex.indexByColumnRow(columnIndex: cDo, rowIndex: r)).value);
    final f = cellHasX(sheet.cell(CellIndex.indexByColumnRow(columnIndex: cFr, rowIndex: r)).value);
    final so = cellHasX(sheet.cell(CellIndex.indexByColumnRow(columnIndex: cSo, rowIndex: r)).value);

    final esc = name.replaceAll("'", r"\'");
    buf.writeln("  ('$esc', $price, $group, $mi, $d, $f, $so),");
  }

  buf.writeln('];');
  buf.writeln('');
  buf.writeln('/// Bei neuer Excel-Version erhoehen — ersetzt Artikel einmalig neu.');
  buf.writeln('const int kArticleCatalogSeedVersion = 4;');
  File(outPath).writeAsStringSync(buf.toString());
  stdout.writeln('Wrote $outPath (${sheet.maxRows - 1} Zeilen geprueft).');
}
