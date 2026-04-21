// dart run tool/build_standard_katalog_xlsx.dart
// Schreibt catalog/Fruehlingsfest.xlsx (Gruppen, Artikel wie Seed, Einstellungen wie Default).
//
// Nur in dieser Vorlagen-Datei (nicht in der App): Supabase fuer Import/Uploader-Vorkonfiguration.

import 'dart:io';

import 'package:excel/excel.dart';
import 'package:vereins_kasse_pro/fruehlingsfest_artikel_seed.dart';

const String kTemplateSupabaseUrl =
    'https://rjghxvhjrxqoahhflsae.supabase.co';
const String kTemplateSupabaseAnonKey =
    'sb_publishable_ReFCB5YenulTdfIi5oyeQw_AaHu0R5R';

void setText(Sheet s, int row, int col, String t) {
  s.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value =
      TextCellValue(t);
}

void setNum(Sheet s, int row, int col, double n) {
  s.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value =
      DoubleCellValue(n);
}

void setInt(Sheet s, int row, int col, int n) {
  s.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value =
      IntCellValue(n);
}

void setMark(Sheet s, int row, int col, bool on) {
  if (on) {
    setText(s, row, col, 'x');
  }
}

void main() {
  final root = Directory.current.path;
  final outFile = File('$root${Platform.pathSeparator}catalog${Platform.pathSeparator}Fruehlingsfest.xlsx');
  outFile.parent.createSync(recursive: true);

  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'Gruppen');

  final gruppen = excel['Gruppen'];
  setText(gruppen, 0, 0, 'ExcelId');
  setText(gruppen, 0, 1, 'Name');
  setInt(gruppen, 1, 0, 1);
  setText(gruppen, 1, 1, 'Getränke');
  setInt(gruppen, 2, 0, 2);
  setText(gruppen, 2, 1, 'Speisen');

  excel['Artikel'];
  final artikel = excel['Artikel'];
  setText(artikel, 0, 0, 'Name');
  setText(artikel, 0, 1, 'Preis');
  setText(artikel, 0, 2, 'Gruppe');
  setText(artikel, 0, 3, 'Mo');
  setText(artikel, 0, 4, 'Di');
  setText(artikel, 0, 5, 'Mi');
  setText(artikel, 0, 6, 'Do');
  setText(artikel, 0, 7, 'Fr');
  setText(artikel, 0, 8, 'Sa');
  setText(artikel, 0, 9, 'So');

  var row = 1;
  for (final e in kFruehlingsfestArtikelSeed) {
    final (name, price, groupExcelId, mi, donnerstag, freitag, sonntag) = e;
    setText(artikel, row, 0, name);
    setNum(artikel, row, 1, price);
    setInt(artikel, row, 2, groupExcelId);
    // Mo, Di, Sa: bewusst leer (Frühlingsfest-Standard); per x setzbar.
    setMark(artikel, row, 5, mi);
    setMark(artikel, row, 6, donnerstag);
    setMark(artikel, row, 7, freitag);
    setMark(artikel, row, 9, sonntag);
    row++;
  }

  excel['Einstellungen'];
  final ein = excel['Einstellungen'];
  setText(ein, 0, 0, 'Schlüssel');
  setText(ein, 0, 1, 'Wert');
  setText(ein, 1, 0, 'Hinweis');
  setText(
    ein,
    1,
    1,
    'Vorlage: supabaseUrl/supabaseAnonKey fuer dieses Repo; App-Defaults bleiben leer.',
  );

  var er = 2;
  void kv(String k, String v) {
    setText(ein, er, 0, k);
    setText(ein, er, 1, v);
    er++;
  }

  kv('dayEnabled_Mo', 'true');
  kv('dayEnabled_Di', 'true');
  kv('dayEnabled_Mi', 'true');
  kv('dayEnabled_Do', 'true');
  kv('dayEnabled_Fr', 'true');
  kv('dayEnabled_Sa', 'true');
  kv('dayEnabled_So', 'true');
  kv('customFields', '');
  kv('presetTableNumbers', '');
  kv('receiptPaneWidth', '160');
  kv('articleColumns', '2');
  kv('articleTileWidth', '1.2');
  kv('articleTileHeight', '0.9');
  kv('articleGroupRows', '1');
  kv('receiptUiScale', '0.8');
  kv('articleUiScale', '0.85');
  kv('showPriceOnTiles', 'true');
  kv('uploadSalesToSupabase', 'true');
  kv('supabaseUrl', kTemplateSupabaseUrl);
  kv('supabaseAnonKey', kTemplateSupabaseAnonKey);
  kv('articleCatalogSeedVersion', kArticleCatalogSeedVersion.toString());

  final bytes = excel.save(fileName: 'Fruehlingsfest.xlsx');
  if (bytes == null) {
    stderr.writeln('excel.save() lieferte null.');
    exitCode = 1;
    return;
  }
  outFile.writeAsBytesSync(bytes);
  stdout.writeln('Wrote ${outFile.path} (${kFruehlingsfestArtikelSeed.length} Artikel).');
}
