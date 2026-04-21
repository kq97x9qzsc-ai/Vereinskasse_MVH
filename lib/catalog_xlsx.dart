import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Standard-Wochentage (wie [WeekdaySelection.dayCodes] in der App).
const kCatalogWeekdayCodes = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// Sichere Defaults fuer fehlende/falsche Einstellungen-Zeilen.
const Map<String, bool> kDefaultDayEnabledMap = {
  'Mo': true,
  'Di': true,
  'Mi': true,
  'Do': true,
  'Fr': true,
  'Sa': true,
  'So': true,
};

class CatalogXlsxException implements Exception {
  CatalogXlsxException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CatalogArticleRow {
  CatalogArticleRow({
    required this.name,
    required this.price,
    required this.groupExcelId,
    required this.weekdays,
    required this.customFields,
  });
  final String name;
  final double price;
  final int groupExcelId;
  /// Schlüssel Mo..So
  final Map<String, bool> weekdays;
  final List<String> customFields;
}

class CatalogXlsxImport {
  CatalogXlsxImport({
    required this.groupsOrdered,
    required this.articleRows,
    this.settingsPatch,
  });

  /// Sortiert nach ExcelId.
  final List<({int excelId, String name})> groupsOrdered;
  final List<CatalogArticleRow> articleRows;

  /// Wenn null: Einstellungen bei Import unveraendert lassen.
  final Map<String, dynamic>? settingsPatch;
}

bool catalogCellHasX(Object? v) {
  final s = v?.toString().trim().toLowerCase() ?? '';
  return s == 'x' || s == '✓' || s == '1' || s == 'true';
}

double catalogParsePrice(Object? v) {
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

int catalogParseInt(Object? v, {int defaultValue = 0}) {
  if (v is int) {
    return v;
  }
  if (v is double) {
    return v.round();
  }
  return int.tryParse(v?.toString().trim() ?? '') ?? defaultValue;
}

bool catalogParseBoolLoose(String raw) {
  final s = raw.trim().toLowerCase();
  return s == 'true' || s == '1' || s == 'ja' || s == 'x';
}

String? _findSheetName(Excel excel, String targetLower) {
  for (final k in excel.tables.keys) {
    if (k.toLowerCase() == targetLower) {
      return k;
    }
  }
  return null;
}

String _header(Sheet sheet, int col) =>
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
        .value
        ?.toString()
        .trim()
        .toLowerCase() ??
    '';

void _setText(Sheet s, int row, int col, String t) {
  s.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value =
      TextCellValue(t);
}

void _setNum(Sheet s, int row, int col, double n) {
  s.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value =
      DoubleCellValue(n);
}

void _setInt(Sheet s, int row, int col, int n) {
  s.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value =
      IntCellValue(n);
}

void _setMark(Sheet s, int row, int col, bool on) {
  if (on) {
    _setText(s, row, col, 'x');
  }
}

/// Erzeugt .xlsx im gleichen Aufbau wie [tool/build_standard_katalog_xlsx.dart] (Fruehlingsfest.xlsx).
List<int>? encodeCatalogXlsx({
  required Map<String, dynamic> settings,
  required List<Map<String, dynamic>> groups,
  required List<Map<String, dynamic>> articles,
}) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'Gruppen');

  final gruppen = excel['Gruppen'];
  _setText(gruppen, 0, 0, 'ExcelId');
  _setText(gruppen, 0, 1, 'Name');
  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    _setInt(gruppen, i + 1, 0, i + 1);
    _setText(gruppen, i + 1, 1, g['name']?.toString() ?? '');
  }

  excel['Artikel'];
  final artikel = excel['Artikel'];
  _setText(artikel, 0, 0, 'Name');
  _setText(artikel, 0, 1, 'Preis');
  _setText(artikel, 0, 2, 'Gruppe');
  for (var c = 0; c < kCatalogWeekdayCodes.length; c++) {
    _setText(artikel, 0, 3 + c, kCatalogWeekdayCodes[c]);
  }
  _setText(artikel, 0, 10, 'Zusatzfelder');

  final idToExcel = <String, int>{};
  for (var i = 0; i < groups.length; i++) {
    idToExcel[groups[i]['id']?.toString() ?? ''] = i + 1;
  }

  var row = 1;
  for (final a in articles) {
    final name = a['name']?.toString() ?? '';
    if (name.isEmpty) {
      continue;
    }
    final price = catalogParsePrice(a['price']);
    final gid = a['groupId']?.toString() ?? '';
    final excelGroup = idToExcel[gid] ?? 1;
    _setText(artikel, row, 0, name);
    _setNum(artikel, row, 1, price);
    _setInt(artikel, row, 2, excelGroup);

    final wd = (a['weekdays'] is Map)
        ? (a['weekdays'] as Map).map(
            (k, v) => MapEntry(k.toString(), v == true),
          )
        : <String, bool>{};
    for (var c = 0; c < kCatalogWeekdayCodes.length; c++) {
      final code = kCatalogWeekdayCodes[c];
      _setMark(artikel, row, 3 + c, wd[code] ?? false);
    }
    final cf = ((a['customFields'] ?? []) as List)
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    _setText(artikel, row, 10, cf.join(';'));
    row++;
  }

  excel['Einstellungen'];
  final ein = excel['Einstellungen'];
  _setText(ein, 0, 0, 'Schlüssel');
  _setText(ein, 0, 1, 'Wert');
  _setText(ein, 1, 0, 'Hinweis');
  _setText(
    ein,
    1,
    1,
    'Export Vereins-Kasse Pro; Zusatzfelder in Artikel durch ; getrennt.',
  );

  var er = 2;
  void kv(String k, String v) {
    _setText(ein, er, 0, k);
    _setText(ein, er, 1, v);
    er++;
  }

  final de = (settings['dayEnabled'] is Map)
      ? (settings['dayEnabled'] as Map).map(
          (k, v) => MapEntry(k.toString(), v == true),
        )
      : Map<String, bool>.from(kDefaultDayEnabledMap);
  for (final d in kCatalogWeekdayCodes) {
    kv('dayEnabled_$d', '${de[d] ?? true}');
  }
  final cf = ((settings['customFields'] ?? []) as List)
      .map((e) => e.toString().trim())
      .where((s) => s.isNotEmpty)
      .join(', ');
  kv('customFields', cf);
  final pt = ((settings['presetTableNumbers'] ?? []) as List)
      .map((e) => e.toString().trim())
      .where((s) => s.isNotEmpty)
      .join(', ');
  kv('presetTableNumbers', pt);
  kv(
    'receiptPaneWidth',
    catalogParsePrice(settings['receiptPaneWidth']).toString(),
  );
  kv('articleColumns', '${catalogParseInt(settings['articleColumns'], defaultValue: 2)}');
  kv('articleTileWidth', catalogParsePrice(settings['articleTileWidth']).toString());
  kv(
    'articleTileHeight',
    catalogParsePrice(settings['articleTileHeight']).toString(),
  );
  kv('articleTileGap', catalogParsePrice(settings['articleTileGap']).toString());
  kv(
    'articleGroupRows',
    '${catalogParseInt(settings['articleGroupRows'], defaultValue: 1)}',
  );
  kv('receiptUiScale', catalogParsePrice(settings['receiptUiScale']).toString());
  kv('articleUiScale', catalogParsePrice(settings['articleUiScale']).toString());
  kv(
    'showPriceOnTiles',
    '${settings['showPriceOnTiles'] != false}',
  );
  kv(
    'uploadSalesToSupabase',
    '${settings['uploadSalesToSupabase'] != false}',
  );
  kv('supabaseUrl', settings['supabaseUrl']?.toString() ?? '');
  kv('supabaseAnonKey', settings['supabaseAnonKey']?.toString() ?? '');
  kv(
    'supabaseStorageBucket',
    settings['supabaseStorageBucket']?.toString() ?? '',
  );
  kv(
    'supabaseStorageObjectPath',
    settings['supabaseStorageObjectPath']?.toString() ?? '',
  );
  kv(
    'articleCatalogSeedVersion',
    '${catalogParseInt(settings['articleCatalogSeedVersion'])}',
  );

  return excel.save(fileName: 'vereins_kasse_katalog.xlsx');
}

Map<String, dynamic>? _parseEinstellungenSheet(Sheet sheet) {
  if (sheet.maxRows < 2) {
    return null;
  }
  final flat = <String, String>{};
  for (var r = 2; r < sheet.maxRows; r++) {
    final k = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
        .value
        ?.toString()
        .trim();
    final v = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
        .value
        ?.toString()
        .trim() ??
        '';
    if (k == null || k.isEmpty || k == 'Hinweis') {
      continue;
    }
    flat[k] = v;
  }
  if (flat.isEmpty) {
    return null;
  }

  final dayEnabled = Map<String, bool>.from(kDefaultDayEnabledMap);
  var touchedDay = false;
  final rest = <String, dynamic>{};

  for (final e in flat.entries) {
    if (e.key.startsWith('dayEnabled_')) {
      final code = e.key.substring('dayEnabled_'.length);
      if (kCatalogWeekdayCodes.contains(code)) {
        dayEnabled[code] = catalogParseBoolLoose(e.value);
        touchedDay = true;
      }
    }
  }
  if (touchedDay) {
    rest['dayEnabled'] = dayEnabled;
  }

  if (flat.containsKey('customFields')) {
    rest['customFields'] = flat['customFields']!
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  if (flat.containsKey('presetTableNumbers')) {
    rest['presetTableNumbers'] = flat['presetTableNumbers']!
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  if (flat.containsKey('receiptPaneWidth')) {
    rest['receiptPaneWidth'] = catalogParsePrice(flat['receiptPaneWidth']);
  }
  if (flat.containsKey('articleColumns')) {
    rest['articleColumns'] = catalogParseInt(
      flat['articleColumns'],
      defaultValue: 2,
    );
  }
  if (flat.containsKey('articleTileWidth')) {
    rest['articleTileWidth'] = catalogParsePrice(flat['articleTileWidth']);
  }
  if (flat.containsKey('articleTileHeight')) {
    rest['articleTileHeight'] = catalogParsePrice(flat['articleTileHeight']);
  }
  if (flat.containsKey('articleTileGap')) {
    rest['articleTileGap'] = catalogParsePrice(flat['articleTileGap']).clamp(
      0,
      24,
    );
  }
  if (flat.containsKey('articleGroupRows')) {
    rest['articleGroupRows'] = catalogParseInt(
      flat['articleGroupRows'],
      defaultValue: 1,
    ).clamp(1, 3);
  }
  if (flat.containsKey('receiptUiScale')) {
    rest['receiptUiScale'] = catalogParsePrice(flat['receiptUiScale']);
  }
  if (flat.containsKey('articleUiScale')) {
    rest['articleUiScale'] = catalogParsePrice(flat['articleUiScale']);
  }
  if (flat.containsKey('showPriceOnTiles')) {
    rest['showPriceOnTiles'] = catalogParseBoolLoose(flat['showPriceOnTiles']!);
  }
  if (flat.containsKey('uploadSalesToSupabase')) {
    rest['uploadSalesToSupabase'] =
        catalogParseBoolLoose(flat['uploadSalesToSupabase']!);
  }
  if (flat.containsKey('supabaseUrl')) {
    rest['supabaseUrl'] = flat['supabaseUrl']!;
  }
  if (flat.containsKey('supabaseAnonKey')) {
    rest['supabaseAnonKey'] = flat['supabaseAnonKey']!;
  }
  if (flat.containsKey('supabaseStorageBucket')) {
    rest['supabaseStorageBucket'] = flat['supabaseStorageBucket']!;
  }
  if (flat.containsKey('supabaseStorageObjectPath')) {
    rest['supabaseStorageObjectPath'] = flat['supabaseStorageObjectPath']!;
  }
  if (flat.containsKey('articleCatalogSeedVersion')) {
    rest['articleCatalogSeedVersion'] = catalogParseInt(
      flat['articleCatalogSeedVersion'],
    );
  }

  return rest;
}

List<({int excelId, String name})> _parseGruppenSheet(Sheet sheet) {
  final rows = <({int excelId, String name})>[];
  for (var r = 1; r < sheet.maxRows; r++) {
    final name = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
        .value
        ?.toString()
        .trim() ??
        '';
    if (name.isEmpty) {
      continue;
    }
    final idCell = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
        .value;
    final excelId = catalogParseInt(idCell, defaultValue: rows.length + 1);
    if (excelId < 1) {
      continue;
    }
    rows.add((excelId: excelId, name: name));
  }
  rows.sort((a, b) => a.excelId.compareTo(b.excelId));
  return rows;
}

/// Liest Katalog-xlsx (Gruppen, Artikel, optional Einstellungen).
CatalogXlsxImport decodeCatalogXlsx(List<int> bytes) {
  late final Excel excel;
  try {
    excel = Excel.decodeBytes(bytes);
  } catch (e) {
    throw CatalogXlsxException('Keine gueltige .xlsx-Datei: $e');
  }

  final artikelName = _findSheetName(excel, 'artikel');
  if (artikelName == null) {
    throw CatalogXlsxException('Blatt „Artikel“ fehlt.');
  }
  final sheet = excel.tables[artikelName]!;

  final legacy = _header(sheet, 3) == 'mi';
  late final int cMi;
  late final int cDo;
  late final int cFr;
  late final int cSa;
  late final int cSo;
  int? cZusatz;

  if (legacy) {
    cMi = 3;
    cDo = 4;
    cFr = 5;
    cSo = 6;
    cSa = -1;
    if (_header(sheet, 7) == 'zusatzfelder') {
      cZusatz = 7;
    }
  } else {
    // Name, Preis, Gruppe, Mo..So [, Zusatzfelder]
    cMi = 5;
    cDo = 6;
    cFr = 7;
    cSa = 8;
    cSo = 9;
    if (_header(sheet, 10) == 'zusatzfelder') {
      cZusatz = 10;
    }
  }

  final articleRows = <CatalogArticleRow>[];
  final seenGroupIds = <int>{};

  for (var r = 1; r < sheet.maxRows; r++) {
    final name = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
        .value
        ?.toString()
        .trim() ??
        '';
    if (name.isEmpty) {
      continue;
    }
    final price = catalogParsePrice(
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value,
    );
    final groupExcelId = catalogParseInt(
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value,
      defaultValue: 1,
    );
    seenGroupIds.add(groupExcelId);

    final wd = <String, bool>{
      for (final d in kCatalogWeekdayCodes) d: false,
    };
    wd['Mi'] = catalogCellHasX(
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: cMi, rowIndex: r)).value,
    );
    wd['Do'] = catalogCellHasX(
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: cDo, rowIndex: r)).value,
    );
    wd['Fr'] = catalogCellHasX(
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: cFr, rowIndex: r)).value,
    );
    wd['So'] = catalogCellHasX(
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: cSo, rowIndex: r)).value,
    );
    if (!legacy && cSa >= 0) {
      wd['Mo'] = catalogCellHasX(
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value,
      );
      wd['Di'] = catalogCellHasX(
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value,
      );
      wd['Sa'] = catalogCellHasX(
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: cSa, rowIndex: r)).value,
      );
    }

    List<String> zf = [];
    if (cZusatz != null) {
      final z = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: cZusatz, rowIndex: r))
          .value
          ?.toString()
          .trim() ??
          '';
      if (z.isNotEmpty) {
        zf = z.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
    }

    articleRows.add(
      CatalogArticleRow(
        name: name,
        price: price,
        groupExcelId: groupExcelId,
        weekdays: wd,
        customFields: zf,
      ),
    );
  }

  Map<String, dynamic>? settingsPatch;
  final einName = _findSheetName(excel, 'einstellungen');
  if (einName != null) {
    settingsPatch = _parseEinstellungenSheet(excel.tables[einName]!);
  }

  List<({int excelId, String name})> groupsOrdered;
  final gruppenName = _findSheetName(excel, 'gruppen');
  if (gruppenName != null) {
    final parsed = _parseGruppenSheet(excel.tables[gruppenName]!);
    groupsOrdered = _mergeGroupIds(parsed, seenGroupIds);
  } else {
    groupsOrdered = _inferGroups(seenGroupIds);
  }

  return CatalogXlsxImport(
    settingsPatch: settingsPatch,
    groupsOrdered: groupsOrdered,
    articleRows: articleRows,
  );
}

List<({int excelId, String name})> _inferGroups(Set<int> ids) {
  final sorted = ids.toList()..sort();
  if (sorted.isEmpty) {
    return [(excelId: 1, name: 'Gruppe 1')];
  }
  return [
    for (final id in sorted) (excelId: id, name: 'Gruppe $id'),
  ];
}

List<({int excelId, String name})> _mergeGroupIds(
  List<({int excelId, String name})> fromSheet,
  Set<int> usedIds,
) {
  final byId = <int, String>{for (final g in fromSheet) g.excelId: g.name};
  for (final id in usedIds) {
    byId.putIfAbsent(id, () => 'Gruppe $id');
  }
  if (byId.isEmpty) {
    return _inferGroups(usedIds);
  }
  final keys = byId.keys.toList()..sort();
  return [for (final k in keys) (excelId: k, name: byId[k]!)];
}

String _normalizeSupabaseObjectPath(String raw) {
  var path = raw.trim();
  path = path.replaceAll(r'\', '/');
  path = path.replaceAll(RegExp(r'/+'), '/');
  path = path.replaceFirst(RegExp(r'^/+'), '');
  if (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

/// Laedt eine Datei aus Supabase Storage (Bucket muss fuer anon lesbar sein).
Future<Uint8List> downloadSupabaseStorageObject({
  required String supabaseUrl,
  required String anonKey,
  required String bucket,
  required String objectPath,
}) async {
  final url = supabaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final key = anonKey.trim();
  final b = bucket.trim();
  var path = _normalizeSupabaseObjectPath(objectPath);
  if (url.isEmpty || key.isEmpty || b.isEmpty || path.isEmpty) {
    throw CatalogXlsxException(
      'URL, Anon Key, Bucket und Dateipfad duerfen nicht leer sein.',
    );
  }
  if (kDebugMode) {
    // Kein Key loggen. Hilft bei 404 (Pfad/Bucket pruefen).
    debugPrint(
      'Supabase Storage download: bucket="$b" objectPath="$path" '
      'url="$url"',
    );
  }
  final client = SupabaseClient(url, key);
  try {
    return await client.storage.from(b).download(path);
  } catch (e) {
    final msg = e.toString();
    var detail = 'Supabase-Download fehlgeschlagen: $e';
    final notFound =
        msg.contains('404') ||
        msg.contains('not_found') ||
        msg.toLowerCase().contains('object not found');
    if (notFound) {
      detail +=
          '\n\nAngefragt: Bucket „$b“, Objektpfad „$path“ (relativ zum '
          'Bucket-Root, ohne fuehrenden /). Im Supabase-Dashboard unter '
          'Storage den exakten Namen pruefen (Groß/Kleinschreibung). '
          'Beispiel: katalog/Fruehlingsfest.xlsx — nicht die volle URL, '
          'nur der Pfad innerhalb des Buckets. '
          'Ohne Leserechte fuer den Anon-Key kann die API statt 403 manchmal '
          '404 liefern.';
    }
    throw CatalogXlsxException(detail);
  }
}
