import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'configure_sqflite_web_stub.dart'
    if (dart.library.html) 'configure_sqflite_web.dart'
    as sqflite_web_cfg;

import 'catalog_xlsx.dart';
import 'fruehlingsfest_artikel_seed.dart';
import 'local_fs.dart';

/// Mindestbreite Belegspalte (Einstellungen + effektive Darstellung).
const double kMinReceiptPaneWidth = 100;
const double kMaxReceiptPaneWidth = 700;
const double kReceiptPaneWidthStep = 20;

/// Mindestbreite fuer den Artikelbereich neben der Belegspalte.
const double kMinArticleStripWidth = 72;
const double kUiScaleMin = 0.55;
const double kUiScaleMax = 1.0;
const double kUiScaleStep = 0.05;

/// Version des lokalen Session-Snapshots (offene Belege, aktueller Beleg, …).
const int kSessionSnapshotVersion = 1;

/// Schriftgroesse in Uebersicht „Alle Belege“ (Listen mit Beleg + Artikel).
const double kReceiptOverviewListTextScale = 1.3;

/// „Offene Belege“: etwas kleiner als [kReceiptOverviewListTextScale] (Faktor 0,9).
const double kReceiptOpenListTextScale =
    kReceiptOverviewListTextScale * 0.9; // 1.17

int _coerceToInt(Object? value, {int defaultValue = 0}) {
  if (value == null) {
    return defaultValue;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value.toString()) ?? defaultValue;
}

String _settingsJsonString(dynamic v) {
  if (v == null) {
    return '';
  }
  return v.toString();
}

double _coerceToDouble(Object? value, {double defaultValue = 0}) {
  if (value == null) {
    return defaultValue;
  }
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString().replaceAll(',', '.')) ?? defaultValue;
}

/// Nur explizit [false] schaltet ab; fehlend/null → null ([SettingsData]-Getter default true).
bool? _parseUploadSalesFlag(Object? value) {
  if (value == false) {
    return false;
  }
  if (value == true) {
    return true;
  }
  return null;
}

/// Artikelname max. 2 Zeilen; bei zu wenig Platz Abschneiden und mit "." enden.
String articleTileLabelTwoLines(String raw, double maxWidth, TextStyle style) {
  if (raw.isEmpty || maxWidth <= 1) {
    return raw;
  }
  final tp = TextPainter(textDirection: ui.TextDirection.ltr, maxLines: 2);
  bool fits(String t) {
    tp.text = TextSpan(text: t, style: style);
    tp.layout(maxWidth: maxWidth);
    return !tp.didExceedMaxLines;
  }

  if (fits(raw)) {
    return raw;
  }
  var lo = 0;
  var hi = raw.length;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    final candidate = '${raw.substring(0, mid)}.';
    if (fits(candidate)) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  if (lo == 0) {
    for (var k = 1; k <= raw.length; k++) {
      final c = '${raw.substring(0, k)}.';
      if (fits(c)) {
        return c;
      }
    }
    return '.';
  }
  return '${raw.substring(0, lo)}.';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    sqflite_web_cfg.configureSqfliteForWeb();
  }
  runApp(const VereinsKasseApp());
}

class VereinsKasseApp extends StatefulWidget {
  const VereinsKasseApp({super.key});

  @override
  State<VereinsKasseApp> createState() => _VereinsKasseAppState();
}

class _VereinsKasseAppState extends State<VereinsKasseApp> {
  bool _batteryDarkMode = true;

  ThemeData _lightTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF5AA9FF),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );
  }

  ThemeData _darkBatteryTheme() {
    const cs = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF5AA9FF),
      onPrimary: Colors.black,
      primaryContainer: Color(0xFF0E3A66),
      onPrimaryContainer: Color(0xFFD6E9FF),
      secondary: Color(0xFF9CC8FF),
      onSecondary: Colors.black,
      secondaryContainer: Color(0xFF243C55),
      onSecondaryContainer: Color(0xFFD9E8FF),
      tertiary: Color(0xFFFFCC80),
      onTertiary: Colors.black,
      tertiaryContainer: Color(0xFF5C4217),
      onTertiaryContainer: Color(0xFFFFE2B8),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF080808),
      onSurface: Color(0xFFF3F3F3),
      onSurfaceVariant: Color(0xFFE0E0E0),
      outline: Color(0xFF8A8A8A),
      outlineVariant: Color(0xFF5A5A5A),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFEAEAEA),
      onInverseSurface: Color(0xFF121212),
      inversePrimary: Color(0xFF2D6EA8),
      surfaceTint: Color(0xFF5AA9FF),
    );

    return ThemeData(
      colorScheme: cs,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      canvasColor: Colors.black,
      cardColor: const Color(0xFF1A1A1A),
      dividerColor: const Color(0xFF464646),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF464646),
        thickness: 1,
      ),
      cardTheme: const CardThemeData(
        color: Color(0xFF1A1A1A),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF151515),
        border: OutlineInputBorder(),
      ),
      useMaterial3: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vereinskasse',
      theme: _lightTheme(),
      darkTheme: _darkBatteryTheme(),
      themeMode: _batteryDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: KasseHomePage(
        onBatteryDarkModeChanged: (enabled) {
          if (_batteryDarkMode == enabled) {
            return;
          }
          setState(() => _batteryDarkMode = enabled);
        },
      ),
    );
  }
}

IconData _articleGroupIcon(String name, {required bool selected}) {
  final flat = name
      .toLowerCase()
      .replaceAll('ä', 'a')
      .replaceAll('ö', 'o')
      .replaceAll('ü', 'u');
  final drinks = flat.contains('getrank') || flat.contains('drink');
  final food = flat.contains('speis') || flat.contains('essen');
  if (drinks) {
    return selected ? Icons.local_drink : Icons.local_drink_outlined;
  }
  if (food) {
    return selected ? Icons.restaurant : Icons.restaurant_outlined;
  }
  return selected ? Icons.category : Icons.category_outlined;
}

String? _articleGroupIdForExcelId(List<ArticleGroup> groups, int excelId) {
  bool isDrinks(String n) {
    final x = n
        .toLowerCase()
        .replaceAll('ä', 'a')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u');
    return x.contains('getrank') || x.contains('drink');
  }

  bool isFood(String n) {
    final x = n
        .toLowerCase()
        .replaceAll('ä', 'a')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u');
    return x.contains('speis') || x.contains('essen');
  }

  if (excelId == 1) {
    for (final g in groups) {
      if (isDrinks(g.name)) {
        return g.id;
      }
    }
    return groups.isNotEmpty ? groups.first.id : null;
  }
  if (excelId == 2) {
    for (final g in groups) {
      if (isFood(g.name)) {
        return g.id;
      }
    }
    return groups.length > 1
        ? groups[1].id
        : (groups.isNotEmpty ? groups.first.id : null);
  }
  return groups.isNotEmpty ? groups.first.id : null;
}

class KasseHomePage extends StatefulWidget {
  const KasseHomePage({super.key, this.onBatteryDarkModeChanged});

  final ValueChanged<bool>? onBatteryDarkModeChanged;

  @override
  State<KasseHomePage> createState() => _KasseHomePageState();
}

class _KasseHomePageState extends State<KasseHomePage>
    with WidgetsBindingObserver {
  final _db = AppDatabase();
  final _supabase = SupabaseUploader();
  final _money = NumberFormat.currency(locale: 'de_DE', symbol: 'EUR ');

  SettingsData settings = SettingsData.defaultValues();
  List<ArticleGroup> groups = [];
  List<Article> articles = [];
  final List<Invoice> openInvoices = [];
  final List<Invoice> allInvoices = [];
  Invoice current = Invoice.next(number: 1);
  Invoice? splitSourceInvoice;

  int selectedGroupTab = 0;
  bool showAllReceipts = false;
  bool showOpenReceipts = false;
  bool hasCreatedReceipt = false;
  bool splitMode = false;
  String selectedWorkday = 'Mo';
  bool _dataReady = false;
  String? _initError;

  /// Offene Eintraege in [upload_queue] (done=0); fuer rote Kopfzeile bei aktivem Supabase-Upload.
  int _pendingUploadCount = 0;
  final ScrollController _receiptLineScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _receiptLineScrollController.dispose();
    super.dispose();
  }

  void _applyNameOrTableSelection(String value) {
    setState(() {
      current.nameOrTable = value;
    });
  }

  Future<void> _showPresetTableNumbersDialog() async {
    var list = List<String>.from(settings.presetTableNumbers);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (outerCtx) {
        var deleteTileMode = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> removePreset(String label) async {
              if (!outerCtx.mounted) {
                return;
              }
              try {
                setLocal(() {
                  list = [...list]..remove(label);
                });
                settings.presetTableNumbers = List<String>.from(list);
                await _db.saveSettings(settings);
              } catch (e, st) {
                debugPrint('Tischnummer loeschen: $e\n$st');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Loeschen fehlgeschlagen: $e')),
                  );
                }
              }
            }

            Future<void> openAddDialog() async {
              final addCtrl = TextEditingController();
              String? created;
              created = await showDialog<String>(
                context: ctx,
                barrierDismissible: true,
                useRootNavigator: false,
                builder: (innerCtx) {
                  var submitted = false;
                  void trySubmit() {
                    if (submitted) {
                      return;
                    }
                    final v = addCtrl.text;
                    if (v.isEmpty) {
                      return;
                    }
                    submitted = true;
                    if (innerCtx.mounted) {
                      Navigator.of(innerCtx).pop<String>(v);
                    }
                  }

                  return AlertDialog(
                    title: const Text('Neue Kachel'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: addCtrl,
                          autofocus: true,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Bezeichnung',
                            hintText: 'Beliebige Zeichen',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => trySubmit(),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: 'Abbrechen',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                if (innerCtx.mounted) {
                                  Navigator.of(innerCtx).pop<String>();
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Uebernehmen',
                              icon: const Icon(Icons.check),
                              onPressed: trySubmit,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );

              if (!outerCtx.mounted) {
                return;
              }
              if (created == null || created.isEmpty) {
                return;
              }
              if (list.contains(created)) {
                return;
              }
              try {
                setLocal(() {
                  list = [...list, created!]..sort();
                });
                settings.presetTableNumbers = List<String>.from(list);
                await _db.saveSettings(settings);
              } catch (e, st) {
                debugPrint('Tischnummer speichern: $e\n$st');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
                  );
                }
              }
            }

            final mq = MediaQuery.sizeOf(ctx);
            final maxDialogBodyH = math.min(420.0, mq.height * 0.55);
            final tileStyle = Theme.of(ctx).textTheme.titleSmall;
            final refTwoDigitPainter = TextPainter(
              text: TextSpan(text: '99', style: tileStyle),
              textDirection: Directionality.of(ctx),
              maxLines: 1,
            )..layout();
            const padEdgeL = 10.0;
            const padEdgeTB = 10.0;
            final minLabelW = refTwoDigitPainter.width * 1.1;
            final minLabelH = refTwoDigitPainter.height * 1.1;
            final minOuterH = (refTwoDigitPainter.height + 2 * padEdgeTB) * 1.1;
            final maxLabelWrapW = mq.width * 0.55;

            const deleteGapW = 6.0;
            const deleteBtnSide = 40.0;

            Widget buildPresetTile(String t) {
              final padR = deleteTileMode ? 8.0 : 10.0;
              final delStrip = deleteTileMode
                  ? deleteGapW + deleteBtnSide
                  : 0.0;
              final labelMaxW = deleteTileMode
                  ? math.max(24.0, maxLabelWrapW - delStrip - padEdgeL - padR)
                  : maxLabelWrapW;
              final lp = TextPainter(
                text: TextSpan(text: t, style: tileStyle),
                textDirection: Directionality.of(ctx),
                maxLines: 4,
              )..layout(maxWidth: labelMaxW);
              final innerW = math.max(minLabelW, lp.size.width);
              final innerH = math.max(minLabelH, lp.size.height);
              final rowW = innerW + delStrip;
              final outerW = padEdgeL + rowW + padR;
              final outerH = math.max(minOuterH, innerH + 2 * padEdgeTB);

              return Material(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: outerW,
                  height: outerH,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: deleteTileMode
                        ? null
                        : () {
                            _applyNameOrTableSelection(t);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (outerCtx.mounted) {
                                Navigator.of(outerCtx).pop<void>();
                              }
                            });
                          },
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          padEdgeL,
                          padEdgeTB,
                          padR,
                          padEdgeTB,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: innerW,
                              height: innerH,
                              child: Center(
                                child: Text(
                                  t,
                                  style: tileStyle,
                                  maxLines: 4,
                                  softWrap: true,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            if (deleteTileMode) ...[
                              SizedBox(width: deleteGapW),
                              Material(
                                color: Theme.of(ctx).colorScheme.errorContainer,
                                shape: const CircleBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: SizedBox(
                                  width: deleteBtnSide,
                                  height: deleteBtnSide,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    style: IconButton.styleFrom(
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      minimumSize: const Size(
                                        deleteBtnSide,
                                        deleteBtnSide,
                                      ),
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    iconSize: 20,
                                    tooltip: 'Kachel loeschen',
                                    icon: Icon(
                                      Icons.close,
                                      color: Theme.of(
                                        ctx,
                                      ).colorScheme.onErrorContainer,
                                    ),
                                    onPressed: () => removePreset(t),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            return AlertDialog(
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(child: Text('Tischnummern')),
                  IconButton(
                    tooltip: 'Hinzufuegen',
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(
                        ctx,
                      ).colorScheme.secondaryContainer,
                      foregroundColor: Theme.of(
                        ctx,
                      ).colorScheme.onSecondaryContainer,
                    ),
                    onPressed: () {
                      if (ctx.mounted) {
                        openAddDialog();
                      }
                    },
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxDialogBodyH),
                  child: SingleChildScrollView(
                    child: list.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Noch keine Nummern.\nOben auf + tippen.',
                              style: Theme.of(ctx).textTheme.bodyMedium,
                            ),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.start,
                            children: [
                              for (final t in list) buildPresetTile(t),
                            ],
                          ),
                  ),
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton(
                  onPressed: () {
                    setLocal(() {
                      deleteTileMode = !deleteTileMode;
                    });
                  },
                  child: Text(deleteTileMode ? 'Abbrechen' : 'Loeschen'),
                ),
                TextButton(
                  onPressed: () {
                    if (outerCtx.mounted) {
                      Navigator.of(outerCtx).pop<void>();
                    }
                  },
                  child: const Text('Schliessen'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_dataReady && _initError == null) {
        _saveSessionSnapshotQuiet();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_dataReady && _initError == null) {
        unawaited(_retryPendingUploads());
      }
    }
  }

  /// Speichert Kassen-Session ohne UI (z. B. App in Hintergrund).
  Future<void> _saveSessionSnapshotQuiet() async {
    try {
      await _db.saveSessionSnapshot(_sessionSnapshotJson());
    } catch (e, st) {
      debugPrint('Session speichern: $e\n$st');
    }
  }

  Map<String, dynamic> _sessionSnapshotJsonMap() => {
    'version': kSessionSnapshotVersion,
    'current': current.toJson(),
    'openInvoices': openInvoices.map((e) => e.toJson()).toList(),
    'allInvoices': allInvoices.map((e) => e.toJson()).toList(),
    'splitSourceInvoice': splitSourceInvoice?.toJson(),
    'splitMode': splitMode,
    'selectedWorkday': selectedWorkday,
    'selectedGroupTab': selectedGroupTab,
    'hasCreatedReceipt': hasCreatedReceipt,
    'showOpenReceipts': showOpenReceipts,
    'showAllReceipts': showAllReceipts,
  };

  String _sessionSnapshotJson() => jsonEncode(_sessionSnapshotJsonMap());

  void _applySessionSnapshot(Map<String, dynamic> map) {
    final ver = _coerceToInt(map['version'], defaultValue: 0);
    if (ver != kSessionSnapshotVersion) {
      return;
    }
    current = Invoice.fromJson((map['current'] as Map).cast<String, dynamic>());
    openInvoices
      ..clear()
      ..addAll(
        ((map['openInvoices'] ?? []) as List).map(
          (e) => Invoice.fromJson((e as Map).cast<String, dynamic>()),
        ),
      );
    allInvoices
      ..clear()
      ..addAll(
        ((map['allInvoices'] ?? []) as List).map(
          (e) => Invoice.fromJson((e as Map).cast<String, dynamic>()),
        ),
      );
    final split = map['splitSourceInvoice'];
    splitSourceInvoice = split == null
        ? null
        : Invoice.fromJson((split as Map).cast<String, dynamic>());
    splitMode = map['splitMode'] == true;
    selectedWorkday = (map['selectedWorkday'] ?? selectedWorkday).toString();
    selectedGroupTab = _coerceToInt(map['selectedGroupTab'], defaultValue: 0);
    hasCreatedReceipt = map['hasCreatedReceipt'] == true;
    if (!hasCreatedReceipt && current.items.isNotEmpty) {
      hasCreatedReceipt = true;
    }
    showOpenReceipts = map['showOpenReceipts'] == true;
    showAllReceipts = map['showAllReceipts'] == true;
  }

  Future<void> _persistKasseSessionAndExitApp() async {
    await _db.saveSessionSnapshot(_sessionSnapshotJson());
    if (!mounted) {
      return;
    }
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Session wurde gespeichert. Bitte Tab/Fenster manuell schliessen.',
          ),
        ),
      );
      return;
    }
    await SystemNavigator.pop();
  }

  Future<void> _initData() async {
    if (mounted) {
      setState(() {
        _dataReady = false;
        _initError = null;
      });
    }
    try {
      await _db.init();
      settings = await _db.loadSettings();
      widget.onBatteryDarkModeChanged?.call(settings.batteryDarkMode);
      groups = await _db.loadGroups();
      articles = await _db.loadArticles();
      selectedWorkday = settings.availableWorkdays.first;
      if (groups.isEmpty) {
        groups = [
          ArticleGroup(id: const Uuid().v4(), name: 'Getränke'),
          ArticleGroup(id: const Uuid().v4(), name: 'Speisen'),
        ];
        for (final g in groups) {
          await _db.upsertGroup(g);
        }
      }
      await _applyFruehlingsfestArticleCatalog();
      _syncSelectedWorkdayToArticles();
      await _retryPendingUploads();
      final snap = await _db.loadSessionSnapshot();
      if (snap != null && snap.isNotEmpty) {
        try {
          _applySessionSnapshot(jsonDecode(snap) as Map<String, dynamic>);
        } catch (e, st) {
          debugPrint('Session laden: $e\n$st');
        }
      }
      if (!hasCreatedReceipt && current.items.isNotEmpty) {
        hasCreatedReceipt = true;
      }
    } catch (e, st) {
      debugPrint('Kasse Init: $e\n$st');
      if (mounted) {
        setState(() => _initError = e.toString());
      }
    }
    if (!mounted) {
      return;
    }
    setState(() => _dataReady = true);
  }

  /// Wenn fuer den gewaehlten Arbeitstag kein Artikel vorgesehen ist (z. B. Katalog nur Mi–So), ersten passenden Tag aus den Einstellungen waehlen.
  void _syncSelectedWorkdayToArticles() {
    if (articles.isEmpty) {
      return;
    }
    bool dayHasArticle(String d) => articles.any(
      (a) => a.weekdays.isDayEnabled(d) || a.customFields.contains(d),
    );
    if (dayHasArticle(selectedWorkday)) {
      return;
    }
    for (final d in settings.availableWorkdays) {
      if (dayHasArticle(d)) {
        selectedWorkday = d;
        return;
      }
    }
  }

  /// Ersetzt Artikel durch Katalog aus [kFruehlingsfestArtikelSeed], wenn [SettingsData.articleCatalogSeedVersion] niedriger ist.
  Future<void> _applyFruehlingsfestArticleCatalog() async {
    if (settings.articleCatalogSeedVersion >= kArticleCatalogSeedVersion) {
      return;
    }
    final drinksId = _articleGroupIdForExcelId(groups, 1);
    final foodId = _articleGroupIdForExcelId(groups, 2);
    if (drinksId == null || foodId == null) {
      return;
    }
    final uuid = const Uuid();
    final list = <Article>[
      for (final row in kFruehlingsfestArtikelSeed)
        Article(
          id: uuid.v4(),
          // Seed nutzt positional records (const) — $1..$7 = Name, Preis, Gruppe, Mi, Do, Fr, So
          name: row.$1.trim(),
          price: row.$2,
          groupId: row.$3 == 2 ? foodId : drinksId,
          weekdays: WeekdaySelection({
            'Mo': false,
            'Di': false,
            'Mi': row.$4,
            'Do': row.$5,
            'Fr': row.$6,
            'Sa': false,
            'So': row.$7,
          }),
          customFields: [],
        ),
    ];
    await _db.replaceArticles(list);
    articles = list;
    settings.articleCatalogSeedVersion = kArticleCatalogSeedVersion;
    await _db.saveSettings(settings);
  }

  Future<void> _syncPendingUploadCountFromDb() async {
    final n = await _db.countPendingUploads();
    if (!mounted) {
      return;
    }
    setState(() => _pendingUploadCount = n);
  }

  /// Versucht alle pending Uploads; aktualisiert [_pendingUploadCount].
  Future<void> _retryPendingUploads() async {
    final queue = await _db.loadUploadQueue();
    for (final q in queue) {
      final ok = await _supabase.tryUpload(
        settings: settings,
        payload: q.payload,
      );
      if (ok) {
        await _db.markQueueDone(q.id);
      }
    }
    await _syncPendingUploadCountFromDb();
  }

  @override
  Widget build(BuildContext context) {
    if (!_dataReady) {
      return PopScope(
        canPop: false,
        child: const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Lade Daten...'),
              ],
            ),
          ),
        ),
      );
    }
    if (_initError != null) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Daten konnten nicht geladen werden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(_initError!, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => _initData(),
                    child: const Text('Erneut versuchen'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final workdays = settings.availableWorkdays;
    if (!workdays.contains(selectedWorkday)) {
      selectedWorkday = workdays.first;
    }
    if (selectedGroupTab >= groups.length && groups.isNotEmpty) {
      selectedGroupTab = 0;
    }

    final pad = MediaQuery.paddingOf(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(
                top: pad.top + 2,
                left: math.max(4.0, pad.left),
                right: math.max(4.0, pad.right),
                bottom: 4,
              ),
              child: _buildHeader(),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: pad.left,
                  right: pad.right,
                  bottom: pad.bottom,
                ),
                child: showOpenReceipts || showAllReceipts
                    ? _buildReceiptPanel(current, editable: true)
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final paneW = _effectiveReceiptPaneWidth(
                            constraints.maxWidth,
                          );
                          return Row(
                            children: [
                              SizedBox(
                                width: paneW,
                                child: _buildReceiptPanel(
                                  current,
                                  editable: true,
                                ),
                              ),
                              const VerticalDivider(width: 1),
                              Expanded(
                                child: splitMode
                                    ? _buildSplitSourcePanel()
                                    : _buildArticleGrid(groups),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Belegspalte: gewünschte [SettingsData.receiptPaneWidth], begrenzt durch Bildschirmbreite (Artikelbereich bleibt nutzbar).
  double _effectiveReceiptPaneWidth(double rowWidth) {
    const divider = 1.0;
    final inner = rowWidth - divider;
    final cap = inner - kMinArticleStripWidth;
    if (cap <= 0) {
      return math.max(0, inner * 0.45);
    }
    final hi = math.min(kMaxReceiptPaneWidth, cap);
    final lo = math.min(kMinReceiptPaneWidth, hi);
    return settings.receiptPaneWidth.clamp(lo, hi);
  }

  /// Kombiniert System-Schriftgrad mit UI-Skalierung aus den Einstellungen.
  Widget _scaledUiSubtree({required double uiScale, required Widget child}) {
    final mq = MediaQuery.of(context);
    final sysFactor = mq.textScaler.scale(16) / 16.0;
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(sysFactor * uiScale)),
      child: child,
    );
  }

  Widget _workdayDropdown({double scale = 1.0}) {
    final workdays = settings.availableWorkdays;
    final effectiveScale = scale.clamp(kUiScaleMin, kUiScaleMax);
    return DropdownButtonFormField<String>(
      initialValue: selectedWorkday,
      isExpanded: true,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: (14 * effectiveScale).clamp(12, 16),
      ),
      decoration: InputDecoration(
        labelText: 'Arbeitstag',
        isDense: false,
        labelStyle: TextStyle(fontSize: (11 * effectiveScale).clamp(10, 13)),
        contentPadding: EdgeInsets.symmetric(
          horizontal: (10 * effectiveScale).clamp(8, 12),
          vertical: (10 * effectiveScale).clamp(8, 12),
        ),
      ),
      items: workdays
          .map(
            (d) => DropdownMenuItem(
              value: d,
              child: Text(
                d,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: (14 * effectiveScale).clamp(12, 16)),
              ),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => selectedWorkday = v ?? workdays.first),
    );
  }

  /// Groessere Schrift in Beleg-Uebersichtslisten; [scale] z. B. offen vs. alle Belege.
  Widget _scaleReceiptOverviewListFont({
    required Widget child,
    double scale = kReceiptOverviewListTextScale,
  }) {
    final mq = MediaQuery.of(context);
    final sys = mq.textScaler.scale(16) / 16.0;
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(sys * scale)),
      child: child,
    );
  }

  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    final rs = settings.receiptUiScale.clamp(kUiScaleMin, kUiScaleMax);
    final uploadBacklog = _pendingUploadCount > 0;
    final headerBg = uploadBacklog
        ? cs.errorContainer
        : cs.surfaceContainerHighest;
    final headerFg = uploadBacklog ? cs.onErrorContainer : null;
    final btnStyle = FilledButton.styleFrom(
      padding: EdgeInsets.symmetric(
        horizontal: (14 * rs).clamp(10, 16),
        vertical: (10 * rs).clamp(8, 12),
      ),
      visualDensity: VisualDensity.standard,
      minimumSize: Size(0, (42 * rs).clamp(36, 48)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: TextStyle(
        fontSize: (14 * rs).clamp(12, 16),
        fontWeight: FontWeight.w600,
        color: headerFg,
      ),
    );
    final iconColor = headerFg ?? cs.onSurfaceVariant;
    return Material(
      color: headerBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: headerFg),
          child: IconTheme.merge(
            data: IconThemeData(color: iconColor),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  FilledButton.tonal(
                    style: btnStyle,
                    onPressed: () => setState(() {
                      showOpenReceipts = true;
                      showAllReceipts = false;
                    }),
                    child: const Text('Offene Belege'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonal(
                    style: btnStyle,
                    onPressed: () => setState(() {
                      showAllReceipts = true;
                      showOpenReceipts = false;
                    }),
                    child: const Text('Alle Belege'),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: math.max(110.0, 124 * rs),
                    child: _workdayDropdown(scale: rs),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonalIcon(
                    style: btnStyle,
                    onPressed: _showRevenueDialog,
                    icon: const Icon(Icons.show_chart),
                    label: const Text('Umsaetze'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonalIcon(
                    style: btnStyle,
                    onPressed: _showSettingsDialog,
                    icon: const Icon(Icons.settings),
                    label: const Text('Einstellungen'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Inhalt von „Offene Belege“: gespeicherte offene Belege plus der aktuelle Beleg auf dem Hauptbildschirm (wenn nicht leer), ohne doppelte Nummer.
  List<Invoice> _openReceiptsListForOverview() {
    final byNumber = <int, Invoice>{for (final o in openInvoices) o.number: o};
    if (!current.isEmpty) {
      byNumber[current.number] = current.copy();
    }
    final out = byNumber.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return out;
  }

  /// Eine Position im offenen Beleg: oben links Stückzahl, oben rechts Zeilensumme (fett), darunter Bezeichnung in einer Zeile (skaliert).
  Widget _buildOpenReceiptPositionTile(
    Invoice invoice,
    InvoiceItem item, {
    required bool editable,
    bool splitReturnToSource = false,
  }) {
    final theme = Theme.of(context);
    final rs = settings.receiptUiScale.clamp(kUiScaleMin, kUiScaleMax);
    final boldLine =
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold) ??
        const TextStyle(fontWeight: FontWeight.bold, fontSize: 17);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: splitReturnToSource
            ? () => _moveOneItemFromCurrentToSplitSource(item)
            : (editable ? () => _editInvoiceItem(invoice, item) : null),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${item.quantity} x', style: boldLine),
                  const Spacer(),
                  Text(
                    _money.format(item.lineTotal),
                    style: boldLine,
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
              SizedBox(height: 2 * rs),
              LayoutBuilder(
                builder: (context, constraints) {
                  return SizedBox(
                    width: constraints.maxWidth,
                    height: 24 * rs,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.articleName,
                        maxLines: 1,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 20,
                        ),
                      ),
                    ),
                  );
                },
              ),
              Divider(
                height: 10,
                thickness: 1,
                color: theme.dividerColor.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptPanel(Invoice invoice, {required bool editable}) {
    if (showAllReceipts) {
      return _scaledUiSubtree(
        uiScale: settings.receiptUiScale,
        child: _allReceiptsPanel(),
      );
    }
    final source = showOpenReceipts ? _openReceiptsListForOverview() : null;
    if (source != null) {
      return _scaledUiSubtree(
        uiScale: settings.receiptUiScale,
        child: _receiptListPanel(source, 'Offene Belege', resumable: true),
      );
    }

    return _scaledUiSubtree(
      uiScale: settings.receiptUiScale,
      child: Padding(
        padding: EdgeInsets.all(
          8 * settings.receiptUiScale.clamp(kUiScaleMin, kUiScaleMax),
        ),
        child: SizedBox.expand(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onLongPress: editable ? _confirmCancelCurrent : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Beleg #${invoice.number}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(_money.format(invoice.total)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: ValueKey<String>(
                  'name_or_table_${invoice.number}_${invoice.nameOrTable}',
                ),
                initialValue: invoice.nameOrTable,
                enabled: editable,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Name / Tisch',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  suffixIcon: editable
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                          tooltip: 'Tischnummern',
                          icon: const Icon(Icons.add),
                          onPressed: _showPresetTableNumbersDialog,
                        )
                      : null,
                ),
                onChanged: (v) => invoice.nameOrTable = v,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Scrollbar(
                  controller: _receiptLineScrollController,
                  child: ListView.builder(
                    primary: false,
                    controller: _receiptLineScrollController,
                    padding: EdgeInsets.zero,
                    itemCount: invoice.items.length,
                    itemBuilder: (context, index) {
                      final item = invoice.items[index];
                      return _buildOpenReceiptPositionTile(
                        invoice,
                        item,
                        editable: editable,
                        splitReturnToSource:
                            splitMode && editable && invoice == current,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Gesamt: ${_money.format(invoice.total)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  FilledButton.icon(
                    onPressed: _newInvoice,
                    icon: const Icon(Icons.add),
                    label: const Text('Neuer Beleg'),
                  ),
                  if (hasCreatedReceipt)
                    FilledButton.icon(
                      onPressed: _openCashDialog,
                      icon: const Icon(Icons.payments),
                      label: const Text('Kasse EUR'),
                    ),
                  if (hasCreatedReceipt)
                    FilledButton.tonal(
                      onPressed: _toggleSplitMode,
                      child: Text(splitMode ? 'Split beenden' : 'Beleg Split'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Anzeige unter „Offene Belege“: Gruppen wie in [groups], pro Gruppe Stueckzahl absteigend.
  List<InvoiceItem> _sortedOpenReceiptItemsForDisplay(Invoice invoice) {
    final rankByName = <String, int>{
      for (var i = 0; i < groups.length; i++) groups[i].name: i,
    };
    int groupRank(InvoiceItem it) {
      final n = it.groupName.trim();
      if (n.isEmpty) {
        return groups.length + 2;
      }
      return rankByName[n] ?? groups.length + 1;
    }

    final sorted = List<InvoiceItem>.from(invoice.items);
    sorted.sort((a, b) {
      final rg = groupRank(a).compareTo(groupRank(b));
      if (rg != 0) {
        return rg;
      }
      return b.quantity.compareTo(a.quantity);
    });
    return sorted;
  }

  /// Zeilen unter dem Datum bei offenen Belegen: Gruppenkopf („Getraenke:“) dann Artikelzeilen.
  List<Widget> _openReceiptLineWidgets(Invoice invoice) {
    final items = _sortedOpenReceiptItemsForDisplay(invoice);
    if (items.isEmpty) {
      return const [];
    }
    final out = <Widget>[];
    String? prevKey;
    var isFirstGroup = true;
    for (final it in items) {
      final g = it.groupName.trim();
      final key = g.isEmpty ? '' : g;
      if (key != prevKey) {
        prevKey = key;
        final header = g.isEmpty ? 'Ohne Gruppe' : g;
        out.add(
          Padding(
            padding: EdgeInsets.only(top: isFirstGroup ? 0 : 8),
            child: Text(
              '$header:',
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
        isFirstGroup = false;
      }
      out.add(
        Text(
          '${it.quantity} x ${it.articleName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return out;
  }

  Widget _receiptOverviewBackButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        minimumSize: const Size(96, 50),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      onPressed: () => setState(() {
        showAllReceipts = false;
        showOpenReceipts = false;
      }),
      child: const Text('Zurueck'),
    );
  }

  Widget _receiptListPanel(
    List<Invoice> list,
    String title, {
    required bool resumable,
  }) {
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                _receiptOverviewBackButton(context),
              ],
            ),
            Expanded(
              child: _scaleReceiptOverviewListFont(
                scale: kReceiptOpenListTextScale,
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final i = list[index];
                    return Card(
                      child: ListTile(
                        title: Text('Beleg #${i.number} (${i.nameOrTable})'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat(
                                'dd.MM.yyyy HH:mm',
                              ).format(i.createdAt),
                            ),
                            ..._openReceiptLineWidgets(i),
                          ],
                        ),
                        onTap: resumable ? () => _resumeOpenInvoice(i) : null,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _allReceiptsPanel() {
    final paid = allInvoices.where((e) => e.isPaid).toList()
      ..sort(
        (a, b) => (b.paidAt ?? b.createdAt).compareTo(a.paidAt ?? a.createdAt),
      );
    final cancelled = allInvoices.where((e) => e.isCancelled).toList()
      ..sort(
        (a, b) => (b.paidAt ?? b.createdAt).compareTo(a.paidAt ?? a.createdAt),
      );

    return DefaultTabController(
      length: 2,
      child: SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    'Alle Belege',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  _receiptOverviewBackButton(context),
                ],
              ),
              const TabBar(
                tabs: [
                  Tab(text: 'Bezahlt'),
                  Tab(text: 'Storniert'),
                ],
              ),
              Expanded(
                child: _scaleReceiptOverviewListFont(
                  scale: kReceiptOpenListTextScale,
                  child: TabBarView(
                    children: [
                      _finalizedInvoiceList(
                        paid,
                        emptyText: 'Keine bezahlten Belege vorhanden.',
                        openDetails: true,
                      ),
                      _finalizedInvoiceList(
                        cancelled,
                        emptyText: 'Keine stornierten Belege vorhanden.',
                        openDetails: false,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _finalizedInvoiceList(
    List<Invoice> list, {
    required String emptyText,
    required bool openDetails,
  }) {
    if (list.isEmpty) {
      return Center(child: Text(emptyText));
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final i = list[index];
        final stamp = i.paidAt ?? i.createdAt;
        return Card(
          child: ListTile(
            title: Text('Beleg #${i.number} (${i.nameOrTable})'),
            subtitle: Text(DateFormat('dd.MM.yyyy HH:mm').format(stamp)),
            trailing: Text(_money.format(i.total)),
            onTap: openDetails ? () => _showInvoiceDetails(i) : null,
          ),
        );
      },
    );
  }

  Future<void> _showInvoiceDetails(Invoice invoice) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Bezahlter Beleg #${invoice.number}'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Name/Tisch: ${invoice.nameOrTable.isEmpty ? '-' : invoice.nameOrTable}',
              ),
              Text(
                'Zeit: ${DateFormat('dd.MM.yyyy HH:mm').format(invoice.paidAt ?? invoice.createdAt)}',
              ),
              const SizedBox(height: 10),
              const Text(
                'Artikel (nur Ansicht)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 260,
                child: ListView.builder(
                  itemCount: invoice.items.length,
                  itemBuilder: (_, idx) {
                    final item = invoice.items[idx];
                    return ListTile(
                      dense: true,
                      title: Text('${item.quantity} x ${item.articleName}'),
                      subtitle: Text('${_money.format(item.unitPrice)} / Stk'),
                      trailing: Text(_money.format(item.lineTotal)),
                    );
                  },
                ),
              ),
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: Text('Gesamt: ${_money.format(invoice.total)}'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schliessen'),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleGrid(List<ArticleGroup> tabGroups) {
    final activeGroup = tabGroups.isEmpty
        ? null
        : tabGroups[selectedGroupTab.clamp(0, tabGroups.length - 1)];
    final visible = articles.where((a) {
      if (activeGroup == null || a.groupId != activeGroup.id) {
        return false;
      }
      return a.weekdays.isDayEnabled(selectedWorkday) ||
          a.customFields.contains(selectedWorkday);
    }).toList();

    final gScale = settings.articleUiScale.clamp(kUiScaleMin, kUiScaleMax);
    final gridPad = 10.0 * gScale;
    final tileGap = settings.articleTileGap.clamp(0.0, 24.0) * gScale;

    return _scaledUiSubtree(
      uiScale: settings.articleUiScale,
      child: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.all(gridPad),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: settings.articleColumns,
                childAspectRatio:
                    settings.articleTileWidth / settings.articleTileHeight,
                crossAxisSpacing: tileGap,
                mainAxisSpacing: tileGap,
              ),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final article = visible[index];
                final nameStyle = Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);
                return InkWell(
                  onTap: () => _addArticleToCurrent(article),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(8 * gScale),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final nameTextStyle =
                              nameStyle ??
                              const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              );
                          final label = articleTileLabelTwoLines(
                            article.name,
                            c.maxWidth,
                            nameTextStyle,
                          );
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.clip,
                                style: nameTextStyle,
                              ),
                              if (settings.showPriceOnTiles)
                                Text(
                                  _money.format(article.price),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.normal),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (tabGroups.isNotEmpty)
            Builder(
              builder: (context) {
                final desiredRows = settings.articleGroupRows.clamp(1, 3);
                final rows = math.min(desiredRows, tabGroups.length);
                final itemsPerRow = (tabGroups.length / rows).ceil();
                final cs = Theme.of(context).colorScheme;
                final rowHeight = rows == 1 ? 80.0 : 52.0;
                final iconSize = rows == 1 ? 24.0 : 18.0;
                final labelStyle = rows == 1
                    ? Theme.of(context).textTheme.titleMedium
                    : Theme.of(context).textTheme.bodyMedium;
                return Material(
                  elevation: 3,
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var r = 0; r < rows; r++) ...[
                        Builder(
                          builder: (_) {
                            final rowStart = r * itemsPerRow;
                            final rowEnd = math.min(
                              (r + 1) * itemsPerRow,
                              tabGroups.length,
                            );
                            final sel = selectedGroupTab.clamp(
                              0,
                              tabGroups.length - 1,
                            );
                            return SizedBox(
                              height: rowHeight,
                              width: double.infinity,
                              child: Row(
                                children: [
                                  for (var i = rowStart; i < rowEnd; i++)
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setState(
                                          () => selectedGroupTab = i,
                                        ),
                                        child: Container(
                                          height: rowHeight,
                                          decoration: BoxDecoration(
                                            color: i == sel
                                                ? cs.primaryContainer
                                                : null,
                                            border: Border(
                                              right: i < rowEnd - 1
                                                  ? BorderSide(
                                                      color: cs.outlineVariant,
                                                    )
                                                  : BorderSide.none,
                                            ),
                                          ),
                                          padding: EdgeInsets.symmetric(
                                            horizontal: rows == 1 ? 12 : 8,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                _articleGroupIcon(
                                                  tabGroups[i].name,
                                                  selected: i == sel,
                                                ),
                                                size: iconSize,
                                              ),
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: LayoutBuilder(
                                                  builder: (context, bc) {
                                                    final twoLines =
                                                        bc.maxWidth < 100;
                                                    return Text(
                                                      tabGroups[i].name,
                                                      maxLines: twoLines
                                                          ? 2
                                                          : 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: labelStyle,
                                                    );
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                        if (r < rows - 1)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: cs.outlineVariant,
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSplitSourcePanel() {
    final source = splitSourceInvoice;
    if (source == null) {
      return const Center(child: Text('Kein Quellbeleg fuer Split vorhanden.'));
    }
    final rs = settings.receiptUiScale.clamp(kUiScaleMin, kUiScaleMax);
    return _scaledUiSubtree(
      uiScale: settings.receiptUiScale,
      child: Padding(
        padding: EdgeInsets.all(8 * rs),
        child: Column(
          children: [
            Text(
              'Split-Quelle: Beleg #${source.number}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: source.items.length,
                itemBuilder: (context, index) {
                  final item = source.items[index];
                  return ListTile(
                    title: Text('${item.quantity} x ${item.articleName}'),
                    subtitle: const Text(
                      'Tippen: 1 Stueck in den linken Beleg',
                    ),
                    onTap: () => _moveOneItemFromSplitSource(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addArticleToCurrent(Article article) {
    final groupName =
        groups.where((g) => g.id == article.groupId).firstOrNull?.name ??
        'Unbekannt';
    setState(() {
      current.addInvoiceItem(
        InvoiceItem(
          articleId: article.id,
          articleName: article.name,
          unitPrice: article.price,
          quantity: 1,
          groupName: groupName,
        ),
      );
      hasCreatedReceipt = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_receiptLineScrollController.hasClients) {
        return;
      }
      _receiptLineScrollController.animateTo(
        _receiptLineScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _editInvoiceItem(Invoice invoice, InvoiceItem item) async {
    final controller = TextEditingController(text: item.quantity.toString());
    int _currentQuantity() {
      return int.tryParse(controller.text) ?? item.quantity;
    }

    void _updateQuantity(int next) {
      controller.text = next.toString();
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    }

    final action = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item.articleName),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Stueckzahl'),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    onPressed: () => setDialogState(() {
                      final next = (_currentQuantity() - 1).clamp(0, 99999);
                      _updateQuantity(next);
                    }),
                    icon: const Icon(Icons.remove),
                    tooltip: 'Stueckzahl verringern',
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _currentQuantity().toString(),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(width: 12),
                  IconButton.filledTonal(
                    onPressed: () => setDialogState(() {
                      final next = (_currentQuantity() + 1).clamp(0, 99999);
                      _updateQuantity(next);
                    }),
                    icon: const Icon(Icons.add),
                    tooltip: 'Stueckzahl erhoehen',
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'delete'),
              child: const Text('Loeschen'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbruch'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (action == null) {
      return;
    }
    setState(() {
      if (action == 'delete') {
        invoice.items.removeWhere((e) => e.articleId == item.articleId);
      } else if (action == 'save') {
        final q = int.tryParse(controller.text) ?? item.quantity;
        if (q <= 0) {
          invoice.items.removeWhere((e) => e.articleId == item.articleId);
        } else {
          item.quantity = q;
        }
      }
    });
  }

  Future<void> _confirmCancelCurrent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wirklich stornieren?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbruch'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ja'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        if (!current.isEmpty) {
          allInvoices.add(
            current.copy()
              ..isCancelled = true
              ..isPaid = false
              ..paidAt = DateTime.now()
              ..workday = selectedWorkday,
          );
        }
        current = Invoice.next(number: _nextInvoiceNumber());
        splitMode = false;
        splitSourceInvoice = null;
      });
    }
  }

  void _newInvoice() {
    setState(() {
      if (!current.isEmpty) {
        openInvoices.add(current.copy());
      }
      current = Invoice.next(number: _nextInvoiceNumber());
      hasCreatedReceipt = true;
      splitMode = false;
      splitSourceInvoice = null;
    });
  }

  void _resumeOpenInvoice(Invoice selected) {
    setState(() {
      if (!current.isEmpty && current.number != selected.number) {
        final alreadyTracked = openInvoices.any(
          (e) => e.number == current.number,
        );
        if (!alreadyTracked) {
          openInvoices.add(current.copy());
        }
      }
      openInvoices.removeWhere((e) => e.number == selected.number);
      current = selected.copy();
      showAllReceipts = false;
      showOpenReceipts = false;
      hasCreatedReceipt = true;
      splitMode = false;
      splitSourceInvoice = null;
    });
  }

  void _toggleSplitMode() {
    setState(() {
      if (!splitMode) {
        if (current.isEmpty) {
          return;
        }
        splitSourceInvoice = current.copy();
        current = Invoice.next(number: _nextInvoiceNumber());
        splitMode = true;
      } else {
        final source = splitSourceInvoice;
        if (source != null) {
          final merged = source.copy();
          for (final it in current.items) {
            merged.addInvoiceItem(it.copy());
          }
          current = merged;
        }
        splitMode = false;
        splitSourceInvoice = null;
      }
    });
  }

  /// Eine Einheit vom linken (aktiven) Beleg zur zurueck zur Split-Quelle (rechts).
  void _moveOneItemFromCurrentToSplitSource(InvoiceItem item) {
    final src = splitSourceInvoice;
    if (src == null || !splitMode) {
      return;
    }
    setState(() {
      final found = current.items.firstWhere(
        (e) => e.articleId == item.articleId,
      );
      if (found.quantity <= 0) {
        return;
      }
      found.quantity -= 1;
      if (found.quantity <= 0) {
        current.items.removeWhere((e) => e.articleId == item.articleId);
      }
      src.addInvoiceItem(
        InvoiceItem(
          articleId: found.articleId,
          articleName: found.articleName,
          unitPrice: found.unitPrice,
          quantity: 1,
          groupName: found.groupName,
        ),
      );
    });
  }

  void _moveOneItemFromSplitSource(InvoiceItem sourceItem) {
    final src = splitSourceInvoice;
    if (src == null) {
      return;
    }
    setState(() {
      final found = src.items.firstWhere(
        (e) => e.articleId == sourceItem.articleId,
      );
      found.quantity -= 1;
      current.addInvoiceItem(
        InvoiceItem(
          articleId: found.articleId,
          articleName: found.articleName,
          unitPrice: found.unitPrice,
          quantity: 1,
          groupName: found.groupName,
        ),
      );
      src.items.removeWhere((e) => e.quantity <= 0);
    });
  }

  Future<void> _openCashDialog() async {
    if (!_dataReady) {
      return;
    }
    final invoice = current;
    if (invoice.isEmpty) {
      return;
    }
    final supabaseIncomplete =
        settings.uploadSalesToSupabase &&
        (settings.supabaseUrl.trim().isEmpty ||
            settings.supabaseAnonKey.trim().isEmpty);
    final result = await showDialog<CashResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CashDialog(
        total: invoice.total,
        supabaseUploadBlocked: supabaseIncomplete,
        supabaseUploadDisabled: !settings.uploadSalesToSupabase,
      ),
    );
    if (result == null) {
      return;
    }
    if (result.paidCash) {
      await _closeInvoiceAsPaid(result);
    }
  }

  Future<void> _closeInvoiceAsPaid(CashResult result) async {
    final tip = (result.roundTo - current.total);
    final closed = current.copy()
      ..paidAt = DateTime.now()
      ..isPaid = true
      ..isCancelled = false
      ..tipAmount = tip > 0 ? tip : 0
      ..workday = selectedWorkday;
    final restFromSplit = splitSourceInvoice?.copy();
    setState(() {
      allInvoices.add(closed);
      openInvoices.removeWhere((e) => e.number == closed.number);
      if (splitMode && restFromSplit != null && !restFromSplit.isEmpty) {
        current = restFromSplit;
      } else {
        current = Invoice.next(number: _nextInvoiceNumber());
      }
      splitMode = false;
      splitSourceInvoice = null;
    });
    await _db.insertCompletedInvoice(closed);
    await _db.insertCompletedInvoiceSummary(closed);

    if (settings.uploadSalesToSupabase) {
      final payload = closed.toSalesPayload();
      final queueId = await _db.enqueueUpload(payload);
      final ok = await _supabase.tryUpload(
        settings: settings,
        payload: payload,
      );
      if (ok) {
        await _db.markQueueDone(queueId);
      }
    }
    await _syncPendingUploadCountFromDb();
  }

  int _nextInvoiceNumber() {
    final pool = [
      current.number,
      ...openInvoices.map((e) => e.number),
      ...allInvoices.map((e) => e.number),
    ];
    if (pool.isEmpty) {
      return 1;
    }
    return pool.reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<void> _showRevenueDialog() async {
    List<CompletedRow> rows = [];
    double tipFromDb = 0;
    try {
      rows = await _db.loadCompletedInvoiceRows();
      tipFromDb = await _db.loadTotalTips();
    } catch (_) {
      rows = [];
      tipFromDb = 0;
    }
    final liveRows = allInvoices
        .where((e) => e.isPaid)
        .expand(
          (inv) => inv.items.map(
            (it) => CompletedRow(
              groupName: it.groupName.isEmpty ? 'Unbekannt' : it.groupName,
              articleName: it.articleName,
              quantity: it.quantity,
              unitPrice: it.unitPrice,
              totalPrice: it.lineTotal,
            ),
          ),
        )
        .toList();
    final sourceRows = rows.isNotEmpty ? rows : liveRows;
    final grouped = <String, double>{};
    var total = 0.0;
    for (final r in sourceRows) {
      final key = r.groupName.isEmpty ? 'Unbekannt' : r.groupName;
      grouped[key] = (grouped[key] ?? 0) + r.totalPrice;
      total += r.totalPrice;
    }
    final tipFromLive = allInvoices
        .where((e) => e.isPaid)
        .fold<double>(0, (s, e) => s + e.tipAmount);
    final tipTotal = tipFromDb > 0 ? tipFromDb : tipFromLive;
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Umsaetze (lokal)'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (grouped.isEmpty)
                const ListTile(
                  title: Text('Noch keine Umsatzdaten vorhanden.'),
                ),
              for (final entry in grouped.entries)
                ListTile(
                  title: Text(entry.key),
                  trailing: Text(_money.format(entry.value)),
                ),
              ListTile(
                title: const Text('Trinkgeld'),
                trailing: Text(_money.format(tipTotal)),
              ),
              const Divider(),
              ListTile(
                title: const Text('Gesamtsumme'),
                trailing: Text(_money.format(total + tipTotal)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schliessen'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSettingsDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (_) => SettingsDialog(
        initialTabIndex: 2,
        initial: settings,
        groups: groups,
        articles: articles,
        onManualSupabaseUpload: () async {
          await _retryPendingUploads();
          if (!mounted) {
            return;
          }
          final left = _pendingUploadCount;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                left == 0
                    ? 'Alle Umsaetze sind bei Supabase eingegangen.'
                    : 'Noch $left ausstehende(r) Upload(s). Netzwerk oder '
                          'Supabase-Zugangsdaten pruefen.',
              ),
            ),
          );
        },
        onSave: (newSettings, newGroups, newArticles) async {
          settings = newSettings;
          widget.onBatteryDarkModeChanged?.call(settings.batteryDarkMode);
          groups = newGroups;
          articles = newArticles;
          if (!settings.availableWorkdays.contains(selectedWorkday)) {
            selectedWorkday = settings.availableWorkdays.first;
          }
          _syncSelectedWorkdayToArticles();
          await _db.saveSettings(settings);
          await _db.replaceGroups(groups);
          await _db.replaceArticles(articles);
          await _retryPendingUploads();
          setState(() {});
        },
        onDeleteAllReceipts: () async {
          await _db.clearAllReceiptsData();
          openInvoices.clear();
          allInvoices.clear();
          current = Invoice.next(number: 1);
          splitMode = false;
          splitSourceInvoice = null;
          showAllReceipts = false;
          showOpenReceipts = false;
          hasCreatedReceipt = false;
          if (mounted) {
            setState(() {});
          }
        },
        onKasseSchliessen: _persistKasseSessionAndExitApp,
        db: _db,
      ),
    );
  }
}

class CashDialog extends StatefulWidget {
  const CashDialog({
    super.key,
    required this.total,
    this.supabaseUploadBlocked = false,
    this.supabaseUploadDisabled = false,
  });

  final double total;

  /// true: Umsaetze-Upload aktiv, aber Supabase nicht konfiguriert — Zahlungsleiste deaktiviert.
  final bool supabaseUploadBlocked;
  final bool supabaseUploadDisabled;

  @override
  State<CashDialog> createState() => _CashDialogState();
}

class _CashDialogState extends State<CashDialog> {
  final givenController = TextEditingController();
  final roundController = TextEditingController();
  final FocusNode givenFocus = FocusNode();
  final FocusNode roundFocus = FocusNode();
  bool tipsMode = false;
  bool _replaceGiven = true;
  bool _replaceRound = true;
  bool _suppressRoundListener = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.total.toStringAsFixed(2);
    givenController.text = initial;
    roundController.text = initial;
    givenController.addListener(_onGivenChanged);
    roundController.addListener(_onRoundChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  void _onGivenChanged() {
    if (!tipsMode) {
      _suppressRoundListener = true;
      if (roundController.text != givenController.text) {
        roundController.text = givenController.text;
      }
      _suppressRoundListener = false;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _onRoundChanged() {
    if (_suppressRoundListener) {
      return;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    givenController.removeListener(_onGivenChanged);
    roundController.removeListener(_onRoundChanged);
    givenFocus.dispose();
    roundFocus.dispose();
    givenController.dispose();
    roundController.dispose();
    super.dispose();
  }

  double get given =>
      double.tryParse(givenController.text.replaceAll(',', '.')) ?? 0;
  double get roundTo =>
      double.tryParse(roundController.text.replaceAll(',', '.')) ?? 0;

  /// Zahlbetrag deckt Rechnung nicht (Gegeben und/oder Aufrunden zu niedrig).
  bool get _incompleteCashPayment =>
      given < widget.total || roundTo < widget.total;

  /// Rückgeld: ohne „Stimmt so!“ = Aufrunden auf − Rechnungssumme; mit „Stimmt so!“ = Gegeben − Aufrunden auf.
  double get rueckgeldDisplay =>
      tipsMode ? (given - roundTo) : (roundTo - widget.total);

  /// Trinkgeld bei „Stimmt so!“: gleiche Differenz (Aufrunden − Zahlbetrag).
  double get trinkgeldDisplay => roundTo - widget.total;

  void _onNumpad(String value) {
    if (!tipsMode) {
      givenController.removeListener(_onGivenChanged);
      final before = _replaceGiven ? '' : givenController.text.trim();
      final next = before.isEmpty ? value : '$before$value';
      givenController.text = next;
      roundController.text = next;
      givenController.addListener(_onGivenChanged);
      _replaceGiven = false;
      _replaceRound = false;
      setState(() {});
      return;
    }
    // Stimmt so: Numpad nur „Aufrunden auf“, nicht „Gegeben“.
    roundController.removeListener(_onRoundChanged);
    setState(() {
      final before = _replaceRound ? '' : roundController.text.trim();
      final next = before.isEmpty ? value : '$before$value';
      roundController.text = next;
      _replaceRound = false;
    });
    roundController.addListener(_onRoundChanged);
  }

  void _onBackspace() {
    if (!tipsMode) {
      givenController.removeListener(_onGivenChanged);
      if (givenController.text.isNotEmpty) {
        givenController.text = givenController.text.substring(
          0,
          givenController.text.length - 1,
        );
      }
      roundController.text = givenController.text;
      givenController.addListener(_onGivenChanged);
      setState(() {});
      return;
    }
    roundController.removeListener(_onRoundChanged);
    setState(() {
      if (roundController.text.isNotEmpty) {
        roundController.text = roundController.text.substring(
          0,
          roundController.text.length - 1,
        );
      }
    });
    roundController.addListener(_onRoundChanged);
  }

  void _selectAll(TextEditingController controller) {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  void _applyTipsMode(bool on) {
    givenController.removeListener(_onGivenChanged);
    roundController.removeListener(_onRoundChanged);
    setState(() {
      tipsMode = on;
      if (!on) {
        roundController.text = givenController.text;
        _replaceGiven = false;
        _replaceRound = false;
      } else {
        _replaceRound = true;
        _replaceGiven = false;
      }
    });
    givenController.addListener(_onGivenChanged);
    roundController.addListener(_onRoundChanged);
    if (on) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        FocusManager.instance.primaryFocus?.unfocus();
        _selectAll(roundController);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final dialogW = math.min(580.0, screenW - 24).clamp(280.0, 580.0);
    final digitStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(58, 54),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    );
    final actionStyle = FilledButton.styleFrom(
      minimumSize: const Size(92, 50),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 16),
    );
    final outlineActionStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(104, 50),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 15),
    );

    final blockPay = widget.supabaseUploadBlocked;

    final givenField = TextField(
      controller: givenController,
      focusNode: givenFocus,
      readOnly: true,
      keyboardType: TextInputType.none,
      enableInteractiveSelection: true,
      showCursor: true,
      decoration: const InputDecoration(labelText: 'Gegeben'),
      onTap: () {
        if (blockPay) {
          return;
        }
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() {
          if (!tipsMode) {
            _replaceGiven = true;
          }
          _selectAll(givenController);
        });
      },
    );
    final roundField = TextField(
      controller: roundController,
      focusNode: roundFocus,
      readOnly: true,
      keyboardType: TextInputType.none,
      enableInteractiveSelection: true,
      showCursor: true,
      decoration: const InputDecoration(labelText: 'Aufrunden auf'),
      onTap: () {
        if (blockPay) {
          return;
        }
        FocusManager.instance.primaryFocus?.unfocus();
        if (!tipsMode) {
          setState(() {
            _replaceGiven = true;
            _selectAll(givenController);
          });
          return;
        }
        setState(() {
          _replaceRound = true;
          _selectAll(roundController);
        });
      },
    );

    final tipsTile = CheckboxListTile(
      value: tipsMode,
      onChanged: blockPay ? null : (v) => _applyTipsMode(v ?? false),
      title: const Text('Stimmt so!'),
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
    final rueckgeldBox = InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Rueckgeld',
        border: OutlineInputBorder(),
      ),
      child: Text(
        rueckgeldDisplay.toStringAsFixed(2),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );

    return AlertDialog(
      title: Text(
        'Kasse - Zahlbetrag: ${widget.total.toStringAsFixed(2)} EUR',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: dialogW,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        givenField,
                        const SizedBox(height: 10),
                        roundField,
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        tipsTile,
                        const SizedBox(height: 10),
                        rueckgeldBox,
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_incompleteCashPayment)
                const Text(
                  'Der Beleg ist nicht vollstaendig bezahlt!',
                  style: TextStyle(color: Colors.red),
                ),
              if (widget.supabaseUploadBlocked) ...[
                const SizedBox(height: 8),
                Text(
                  'Supabase-Upload einrichten oder Haken bei „Umsaetze uploaden“ entfernen!',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else if (tipsMode) ...[
                const SizedBox(height: 8),
                Text(
                  'Trinkgeld: ${trinkgeldDisplay.toStringAsFixed(2)} EUR',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
              const SizedBox(height: 14),
              Opacity(
                opacity: blockPay ? 0.45 : 1,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final n in [
                      '1',
                      '2',
                      '3',
                      '4',
                      '5',
                      '6',
                      '7',
                      '8',
                      '9',
                      '0',
                      ',',
                      '00',
                    ])
                      OutlinedButton(
                        style: digitStyle,
                        onPressed: blockPay ? null : () => _onNumpad(n),
                        child: Text(n),
                      ),
                    FilledButton(
                      style: actionStyle,
                      onPressed: blockPay || _incompleteCashPayment
                          ? null
                          : () => Navigator.pop(
                              context,
                              CashResult(paidCash: true, roundTo: roundTo),
                            ),
                      child: const Text('Bar'),
                    ),
                    OutlinedButton(
                      style: outlineActionStyle,
                      onPressed: blockPay ? null : _onBackspace,
                      child: const Text('Loeschen'),
                    ),
                  ],
                ),
              ),
              if (widget.supabaseUploadDisabled) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Text(
                    'Achtung kein Umsatz Upload eingestellt!',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbruch'),
        ),
      ],
    );
  }
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    this.initialTabIndex = 0,
    required this.initial,
    required this.groups,
    required this.articles,
    required this.onSave,
    required this.onDeleteAllReceipts,
    required this.db,
    this.onKasseSchliessen,
    this.onManualSupabaseUpload,
  });

  final int initialTabIndex;
  final SettingsData initial;
  final List<ArticleGroup> groups;
  final List<Article> articles;
  final AppDatabase db;
  final Future<void> Function(SettingsData, List<ArticleGroup>, List<Article>)
  onSave;
  final Future<void> Function() onDeleteAllReceipts;

  /// Speichert Session und beendet die App (nur ueber diesen Weg).
  final Future<void> Function()? onKasseSchliessen;

  /// Umsatz-Upload aus der Warteschlange erneut anstossen (Hauptfenster).
  final Future<void> Function()? onManualSupabaseUpload;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late SettingsData localSettings;
  late List<ArticleGroup> localGroups;
  late List<Article> localArticles;
  final Map<String, GlobalKey> _articleTileKeys = {};
  final Map<String, TextEditingController> _articlePosControllers = {};
  final Map<String, FocusNode> _articlePosFocusNodes = {};
  final ScrollController _groupScrollController = ScrollController();
  final ScrollController _articleScrollController = ScrollController();
  String? _pendingAutofocusArticleId;
  String? _expandedArticleId;

  Future<void> _persistChangesInBackground() async {
    await widget.onSave(localSettings, localGroups, localArticles);
  }

  double _measurePosDigitsWidth(String digits, TextStyle style) {
    final s = digits.isEmpty ? '0' : digits;
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    // Reserve extra width so iPhone does not clip multi-digit positions.
    return math.max(26.0, tp.width + 10);
  }

  void _scheduleClearPendingArticleAutofocus() {
    if (_pendingAutofocusArticleId == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (mounted) {
          setState(() => _pendingAutofocusArticleId = null);
        }
      });
    });
  }

  TextEditingController _posControllerFor(String articleId, int index1Based) {
    final existing = _articlePosControllers[articleId];
    if (existing == null) {
      final c = TextEditingController(text: '$index1Based');
      _articlePosControllers[articleId] = c;
      return c;
    }
    return existing;
  }

  FocusNode _posFocusFor(String articleId) {
    return _articlePosFocusNodes.putIfAbsent(articleId, () {
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus) {
          _syncArticlePositionDisplay(articleId);
        }
      });
      return node;
    });
  }

  void _syncArticlePositionDisplay(String articleId) {
    final idx = localArticles.indexWhere((a) => a.id == articleId);
    if (idx < 0) {
      return;
    }
    final c = _articlePosControllers[articleId];
    if (c == null) {
      return;
    }
    final want = '${idx + 1}';
    if (c.text != want) {
      c.text = want;
    }
  }

  void _syncAllArticlePositionDisplays() {
    for (var i = 0; i < localArticles.length; i++) {
      final id = localArticles[i].id;
      final f = _articlePosFocusNodes[id];
      if (f != null && f.hasFocus) {
        continue;
      }
      final c = _articlePosControllers[id];
      if (c == null) {
        continue;
      }
      final want = '${i + 1}';
      if (c.text != want) {
        c.text = want;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    localSettings = widget.initial.copy();
    localGroups = widget.groups.map((e) => e.copy()).toList();
    localArticles = widget.articles.map((e) => e.copy()).toList();
  }

  @override
  void dispose() {
    for (final c in _articlePosControllers.values) {
      c.dispose();
    }
    _articlePosControllers.clear();
    for (final f in _articlePosFocusNodes.values) {
      f.dispose();
    }
    _articlePosFocusNodes.clear();
    _groupScrollController.dispose();
    _articleScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mqSize = MediaQuery.sizeOf(context);
    final narrow = mqSize.width < 520;
    return Dialog(
      insetPadding: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: mqSize.width,
        height: mqSize.height,
        child: SafeArea(
          child: DefaultTabController(
            length: 3,
            initialIndex: widget.initialTabIndex.clamp(0, 2),
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Artikelgruppen'),
                    Tab(text: 'Artikel'),
                    Tab(text: 'Einstellungen'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [_groupsTab(), _articlesTab(), _settingsTab()],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: () {
                          final s = localSettings.copy();
                          final g = localGroups.map((e) => e.copy()).toList();
                          final a = localArticles.map((e) => e.copy()).toList();
                          unawaited(widget.onSave(s, g, a));
                        },
                        child: const Text('Zwischenspeichern'),
                      ),
                      TextButton(
                        onPressed: () {
                          final s = localSettings.copy();
                          final g = localGroups.map((e) => e.copy()).toList();
                          final a = localArticles.map((e) => e.copy()).toList();
                          Navigator.pop(context);
                          unawaited(widget.onSave(s, g, a));
                        },
                        child: Text(
                          narrow
                              ? 'Speichern und\nschliessen'
                              : 'Speichern und schliessen',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _groupsTab() {
    return Column(
      children: [
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(onPressed: _addGroup, child: const Text('+ Neu')),
          ],
        ),
        Expanded(
          child: ListView.builder(
            controller: _groupScrollController,
            itemCount: localGroups.length,
            itemBuilder: (_, i) {
              final g = localGroups[i];
              return Column(
                key: ValueKey('group_${g.id}'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${i + 1}. Artikelgruppe',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                key: ValueKey('group_name_${g.id}'),
                                initialValue: g.name,
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                onChanged: (v) {
                                  g.name = v;
                                },
                              ),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Kopieren',
                                  onPressed: () => _copyGroupAt(i),
                                  icon: const Icon(Icons.copy_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Loeschen',
                                  onPressed: () => _deleteGroupAt(i),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Nach oben',
                                  onPressed: i > 0
                                      ? () => _moveGroup(i, i - 1)
                                      : null,
                                  icon: const Icon(Icons.keyboard_arrow_up),
                                ),
                                IconButton(
                                  tooltip: 'Nach unten',
                                  onPressed: i < localGroups.length - 1
                                      ? () => _moveGroup(i, i + 1)
                                      : null,
                                  icon: const Icon(Icons.keyboard_arrow_down),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (i < localGroups.length - 1) const Divider(height: 1),
                ],
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Anzeige auf Hauptbildschirm (Artikelgruppen-Reihen)'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                children: [
                  for (final rows in [1, 2, 3])
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: localSettings.articleGroupRows == rows,
                          onChanged: localGroups.length >= rows
                              ? (_) => setState(
                                  () => localSettings.articleGroupRows = rows,
                                )
                              : null,
                        ),
                        Text('$rows Reihe${rows == 1 ? '' : 'n'}'),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _articlesTab() {
    final cs = Theme.of(context).colorScheme;
    final articleRowStyle = TextStyle(
      fontSize: 12,
      height: 1.15,
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
    );
    final articleDetailStyle = TextStyle(
      fontSize: 12,
      height: 1.2,
      color: cs.onSurface,
    );
    final chipLabelStyle = TextStyle(fontSize: 11, color: cs.onSurface);
    final fieldDenseDecoration = InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      labelStyle: articleDetailStyle.copyWith(color: cs.onSurfaceVariant),
    );
    final activeWeekdays = WeekdaySelection.dayCodes
        .where((d) => localSettings.dayEnabled[d] ?? true)
        .toList();
    final activeCustomFields = List<String>.from(localSettings.customFields);
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 420;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _addArticle,
                  child: const Text('+ Neu'),
                ),
                OutlinedButton.icon(
                  onPressed: _confirmDeleteAllArticles,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: Text(
                    narrow ? 'Alle Artikel\nloeschen' : 'Alle Artikel loeschen',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          },
        ),
        Expanded(
          child: ListView.builder(
            controller: _articleScrollController,
            itemCount: localArticles.length,
            itemBuilder: (_, i) {
              final a = localArticles[i];
              final expanded = _expandedArticleId == a.id;
              final tileKey = _articleTileKeys.putIfAbsent(a.id, GlobalKey.new);
              final posCtrl = _posControllerFor(a.id, i + 1);
              final posFocus = _posFocusFor(a.id);
              final headStyle = articleRowStyle;
              final posW = _measurePosDigitsWidth(
                posCtrl.text.isEmpty ? '${i + 1}' : posCtrl.text,
                headStyle,
              );
              return Card(
                key: tileKey,
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: ExpansionTile(
                  key: ValueKey('article_tile_${a.id}_$expanded'),
                  maintainState: false,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  childrenPadding: EdgeInsets.zero,
                  initiallyExpanded: expanded,
                  onExpansionChanged: (isOpen) {
                    setState(() {
                      _expandedArticleId = isOpen ? a.id : null;
                    });
                  },
                  title: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: posW,
                            child: TextField(
                              controller: posCtrl,
                              focusNode: posFocus,
                              textAlign: TextAlign.right,
                              keyboardType: TextInputType.number,
                              style: headStyle,
                              decoration: const InputDecoration(
                                isDense: true,
                                isCollapsed: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onTap: () {
                                posCtrl.selection = TextSelection(
                                  baseOffset: 0,
                                  extentOffset: posCtrl.text.length,
                                );
                              },
                              onSubmitted: (v) =>
                                  _moveArticleToTypedPosition(a.id, v),
                            ),
                          ),
                          Text('.', style: headStyle),
                          const SizedBox(width: 6),
                        ],
                      ),
                      Expanded(
                        child: Text(
                          a.name.trim().isEmpty
                              ? '(ohne Bezeichnung)'
                              : a.name.trim(),
                          style: headStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Nach oben',
                            padding: const EdgeInsets.all(2),
                            constraints: const BoxConstraints(
                              minWidth: 34,
                              minHeight: 34,
                            ),
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            iconSize: 26,
                            onPressed: i > 0
                                ? () => _moveArticle(i, i - 1)
                                : null,
                            icon: const Icon(Icons.keyboard_arrow_up),
                          ),
                          IconButton(
                            tooltip: 'Nach unten',
                            padding: const EdgeInsets.all(2),
                            constraints: const BoxConstraints(
                              minWidth: 34,
                              minHeight: 34,
                            ),
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            iconSize: 26,
                            onPressed: i < localArticles.length - 1
                                ? () => _moveArticle(i, i + 1)
                                : null,
                            icon: const Icon(Icons.keyboard_arrow_down),
                          ),
                          IconButton(
                            tooltip: 'Kopieren',
                            padding: const EdgeInsets.all(2),
                            constraints: const BoxConstraints(
                              minWidth: 34,
                              minHeight: 34,
                            ),
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            iconSize: 26,
                            onPressed: () => _copyArticleAt(i),
                            icon: const Icon(Icons.copy_outlined),
                          ),
                          IconButton(
                            tooltip: 'Loeschen',
                            padding: const EdgeInsets.all(2),
                            constraints: const BoxConstraints(
                              minWidth: 34,
                              minHeight: 34,
                            ),
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            iconSize: 26,
                            onPressed: () => _deleteArticleAt(i),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                      child: Column(
                        children: [
                          TextFormField(
                            key: ValueKey('article_name_${a.id}'),
                            autofocus: _pendingAutofocusArticleId == a.id,
                            initialValue: a.name,
                            style: articleDetailStyle,
                            decoration: fieldDenseDecoration.copyWith(
                              labelText: 'Bezeichnung',
                            ),
                            onChanged: (v) => setState(() {
                              a.name = v;
                            }),
                          ),
                          TextFormField(
                            initialValue: a.price.toStringAsFixed(2),
                            style: articleDetailStyle,
                            decoration: fieldDenseDecoration.copyWith(
                              labelText: 'Preis (EUR/Stueck)',
                            ),
                            onChanged: (v) => a.price =
                                double.tryParse(v.replaceAll(',', '.')) ??
                                a.price,
                          ),
                          DropdownButtonFormField<String>(
                            initialValue: a.groupId,
                            style: articleDetailStyle,
                            items: localGroups
                                .map(
                                  (g) => DropdownMenuItem(
                                    value: g.id,
                                    child: Text(
                                      g.name,
                                      style: articleDetailStyle,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() {
                              a.groupId = v ?? a.groupId;
                            }),
                            decoration: fieldDenseDecoration.copyWith(
                              labelText: 'Artikelgruppe',
                            ),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Sichtbare Felder fuer Artikel',
                              style: articleDetailStyle.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final d in activeWeekdays)
                                FilterChip(
                                  label: Text(d, style: chipLabelStyle),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  selected: a.weekdays.isDayEnabled(d),
                                  onSelected: (selected) => setState(() {
                                    a.weekdays.values[d] = selected;
                                  }),
                                ),
                              for (final f in activeCustomFields)
                                FilterChip(
                                  label: Text(f, style: chipLabelStyle),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  selected: a.customFields.contains(f),
                                  onSelected: (selected) => setState(() {
                                    if (selected) {
                                      if (!a.customFields.contains(f)) {
                                        a.customFields.add(f);
                                      }
                                    } else {
                                      a.customFields.remove(f);
                                    }
                                  }),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _settingsTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          const Text('Wochentage'),
          Wrap(
            spacing: 8,
            children: WeekdaySelection.dayCodes.map((d) {
              final checked = localSettings.dayEnabled[d] ?? true;
              return FilterChip(
                label: Text(d),
                selected: checked,
                onSelected: (v) =>
                    setState(() => localSettings.dayEnabled[d] = v),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Eigene Felder'),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _addCustomField,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          ...List.generate(localSettings.customFields.length, (i) {
            final f = localSettings.customFields[i];
            return ListTile(
              title: Text(f),
              trailing: IconButton(
                onPressed: () => setState(() {
                  localSettings.customFields.removeAt(i);
                  for (final a in localArticles) {
                    a.customFields.remove(f);
                  }
                }),
                icon: const Icon(Icons.delete_outline),
              ),
            );
          }),
          const Divider(height: 28),
          const Text(
            'Darstellung',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          SwitchListTile(
            value: localSettings.batteryDarkMode,
            onChanged: (v) => setState(() => localSettings.batteryDarkMode = v),
            title: const Text('Energiespar-Dunkelmodus'),
            subtitle: const Text(
              'AMOLED-Schwarz mit hohem Kontrast fuer lange Nutzung und bessere Lesbarkeit.',
              style: TextStyle(fontSize: 12),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 28),
          const Text(
            'Supabase – Umsaetze uploaden',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            value: localSettings.uploadSalesToSupabase,
            onChanged: (v) =>
                setState(() => localSettings.uploadSalesToSupabase = v ?? true),
            title: const Text('Umsaetze uploaden'),
            subtitle: const Text(
              'Wenn aktiv, sind Bar-Zahlung und Numpad erst nutzbar, '
              'nachdem Supabase-URL und Anon Key eingetragen sind.',
              style: TextStyle(fontSize: 12),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          if (widget.onManualSupabaseUpload != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Ausstehende Belege erneut zu Supabase senden.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: !localSettings.uploadSalesToSupabase
                      ? null
                      : () async {
                          await widget.onManualSupabaseUpload!();
                        },
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Jetzt hochladen'),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          TextFormField(
            initialValue: localSettings.supabaseUrl,
            decoration: const InputDecoration(labelText: 'Supabase URL'),
            onChanged: (v) => localSettings.supabaseUrl = v.trim(),
          ),
          TextFormField(
            initialValue: localSettings.supabaseAnonKey,
            decoration: const InputDecoration(labelText: 'Supabase Anon Key'),
            obscureText: true,
            onChanged: (v) => localSettings.supabaseAnonKey = v.trim(),
          ),
          const Divider(height: 28),
          const Text('Anpassung Beleganzeige'),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => localSettings.receiptPaneWidth =
                      (localSettings.receiptPaneWidth - kReceiptPaneWidthStep)
                          .clamp(kMinReceiptPaneWidth, kMaxReceiptPaneWidth),
                ),
                icon: const Icon(Icons.arrow_left),
              ),
              Expanded(
                child: Text(
                  'Breite: ${localSettings.receiptPaneWidth.toStringAsFixed(0)} px',
                ),
              ),
              IconButton(
                onPressed: () => setState(
                  () => localSettings.receiptPaneWidth =
                      (localSettings.receiptPaneWidth + kReceiptPaneWidthStep)
                          .clamp(kMinReceiptPaneWidth, kMaxReceiptPaneWidth),
                ),
                icon: const Icon(Icons.arrow_right),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Beleg Schrift/Buttons (separat)',
            style: TextStyle(fontSize: 13),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => localSettings.receiptUiScale =
                      (localSettings.receiptUiScale - kUiScaleStep).clamp(
                        kUiScaleMin,
                        kUiScaleMax,
                      ),
                ),
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: Text(
                  'Skala: ${(localSettings.receiptUiScale * 100).round()} %',
                ),
              ),
              IconButton(
                onPressed: () => setState(
                  () => localSettings.receiptUiScale =
                      (localSettings.receiptUiScale + kUiScaleStep).clamp(
                        kUiScaleMin,
                        kUiScaleMax,
                      ),
                ),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const Divider(),
          const Text('Anpassung Artikelanzeige'),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => localSettings.articleTileHeight =
                      (localSettings.articleTileHeight - 0.1).clamp(0.7, 2.5),
                ),
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                onPressed: () => setState(
                  () => localSettings.articleTileHeight =
                      (localSettings.articleTileHeight + 0.1).clamp(0.7, 2.5),
                ),
                icon: const Icon(Icons.arrow_downward),
              ),
              Expanded(
                child: Text(
                  'Kachelhoehe: ${localSettings.articleTileHeight.toStringAsFixed(1)}',
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => localSettings.articleTileWidth =
                      (localSettings.articleTileWidth - 0.1).clamp(0.75, 2.2),
                ),
                icon: const Icon(Icons.arrow_left),
              ),
              IconButton(
                onPressed: () => setState(
                  () => localSettings.articleTileWidth =
                      (localSettings.articleTileWidth + 0.1).clamp(0.75, 2.2),
                ),
                icon: const Icon(Icons.arrow_right),
              ),
              Expanded(
                child: Text(
                  'Kachelbreite (Verhaeltnis): ${localSettings.articleTileWidth.toStringAsFixed(1)}',
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => localSettings.articleTileGap =
                      (localSettings.articleTileGap - 1).clamp(0, 24),
                ),
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: Text(
                  'Kachelabstand: ${localSettings.articleTileGap.toStringAsFixed(0)} px',
                ),
              ),
              IconButton(
                onPressed: () => setState(
                  () => localSettings.articleTileGap =
                      (localSettings.articleTileGap + 1).clamp(0, 24),
                ),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Artikel Schrift/Labels (separat)',
            style: TextStyle(fontSize: 13),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => localSettings.articleUiScale =
                      (localSettings.articleUiScale - kUiScaleStep).clamp(
                        kUiScaleMin,
                        kUiScaleMax,
                      ),
                ),
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: Text(
                  'Skala: ${(localSettings.articleUiScale * 100).round()} %',
                ),
              ),
              IconButton(
                onPressed: () => setState(
                  () => localSettings.articleUiScale =
                      (localSettings.articleUiScale + kUiScaleStep).clamp(
                        kUiScaleMin,
                        kUiScaleMax,
                      ),
                ),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => localSettings.articleColumns =
                      (localSettings.articleColumns - 1).clamp(1, 6),
                ),
                icon: const Icon(Icons.arrow_left),
              ),
              Text('Spalten: ${localSettings.articleColumns}'),
              IconButton(
                onPressed: () => setState(
                  () => localSettings.articleColumns =
                      (localSettings.articleColumns + 1).clamp(1, 6),
                ),
                icon: const Icon(Icons.arrow_right),
              ),
            ],
          ),
          SwitchListTile(
            value: localSettings.showPriceOnTiles,
            onChanged: (v) =>
                setState(() => localSettings.showPriceOnTiles = v),
            title: const Text('Preis auf Kacheln anzeigen'),
          ),
          const Divider(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _exportCatalogXlsx,
                child: const Text('Export'),
              ),
              FilledButton.tonal(
                onPressed: _importData,
                child: const Text('Import'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: _showSupabaseCatalogDownloadDialog,
              child: const Text('Download Daten'),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _confirmDeleteRevenueData,
                child: const Text('Umsatzdaten loeschen'),
              ),
              FilledButton(
                onPressed: _confirmDeleteAllReceipts,
                child: const Text('Alle Belege loeschen'),
              ),
            ],
          ),
          if (widget.onKasseSchliessen != null) ...[
            const Divider(),
            const Text(
              'Kasse beenden',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Speichert alle offenen Belege, die Belegliste und den Kassenstand '
              'und beendet die App. Umsaetze in der Datenbank bleiben erhalten. '
              'Die System-Zurueck-Taste schliesst die App nicht.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _onKasseSchliessenPressed,
              icon: const Icon(Icons.power_settings_new),
              label: const Text('Kasse schliessen'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _onKasseSchliessenPressed() async {
    if (widget.onKasseSchliessen == null) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kasse schliessen?'),
        content: const Text(
          'Alle Belege und der aktuelle Stand werden gespeichert. '
          'Die App wird beendet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbruch'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Speichern und beenden'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    await widget.onSave(localSettings, localGroups, localArticles);
    if (!mounted) {
      return;
    }
    Navigator.pop(context);
    await widget.onKasseSchliessen!();
  }

  void _addGroup() => setState(() {
    localGroups.add(ArticleGroup(id: const Uuid().v4(), name: 'Neue Gruppe'));
    _scrollGroupsToEnd();
  });
  void _moveGroup(int from, int to) {
    if (from < 0 ||
        to < 0 ||
        from >= localGroups.length ||
        to >= localGroups.length ||
        from == to) {
      return;
    }
    setState(() {
      final item = localGroups.removeAt(from);
      localGroups.insert(to, item);
    });
    _scrollToGroupIndex(to);
  }

  void _copyGroupAt(int sourceIndex) {
    if (localGroups.isEmpty ||
        sourceIndex < 0 ||
        sourceIndex >= localGroups.length) {
      return;
    }
    final src = localGroups[sourceIndex];
    setState(() {
      localGroups.insert(
        sourceIndex + 1,
        ArticleGroup(id: const Uuid().v4(), name: '${src.name} Kopie'),
      );
    });
  }

  Future<void> _deleteGroupAt(int sourceIndex) async {
    if (localGroups.isEmpty ||
        sourceIndex < 0 ||
        sourceIndex >= localGroups.length) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sind Sie sich sicher?'),
        content: const Text(
          'Alle dazugehoerigen Artikel werden ebenfalls geloescht!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbruch'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ja, loeschen'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final id = localGroups[sourceIndex].id;
    setState(() {
      localGroups.removeAt(sourceIndex);
      localArticles.removeWhere((a) => a.groupId == id);
    });
  }

  void _moveArticle(int from, int to, {bool autoScroll = true}) {
    if (from < 0 ||
        to < 0 ||
        from >= localArticles.length ||
        to >= localArticles.length ||
        from == to) {
      return;
    }
    setState(() {
      final item = localArticles.removeAt(from);
      localArticles.insert(to, item);
      _expandedArticleId = null;
    });
    _syncAllArticlePositionDisplays();
    if (autoScroll) {
      _scrollArticleToTop(localArticles[to].id);
    }
  }

  void _moveArticleToTypedPosition(String articleId, String raw) {
    final fromIndex = localArticles.indexWhere((a) => a.id == articleId);
    if (fromIndex < 0 || localArticles.isEmpty) {
      return;
    }
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) {
      _syncArticlePositionDisplay(articleId);
      return;
    }
    final target = parsed.clamp(1, localArticles.length) - 1;
    if (target == fromIndex) {
      _syncArticlePositionDisplay(articleId);
      return;
    }
    _moveArticle(fromIndex, target, autoScroll: false);
    final c = _articlePosControllers[articleId];
    if (c != null) {
      c.text = '${target + 1}';
    }
  }

  void _addArticle() {
    if (localGroups.isEmpty) return;
    final weekdayDefaults = {
      for (final d in WeekdaySelection.dayCodes)
        d: (localSettings.dayEnabled[d] ?? true),
    };
    setState(() {
      final id = const Uuid().v4();
      localArticles.add(
        Article(
          id: id,
          name: 'Neuer Artikel',
          price: 1,
          groupId: localGroups.first.id,
          weekdays: WeekdaySelection(weekdayDefaults),
          customFields: List<String>.from(localSettings.customFields),
        ),
      );
      _pendingAutofocusArticleId = id;
      _expandedArticleId = id;
    });
    _syncAllArticlePositionDisplays();
    _scrollArticlesToEnd();
    _scheduleClearPendingArticleAutofocus();
  }

  void _copyArticleAt(int index) {
    if (localArticles.isEmpty || index < 0 || index >= localArticles.length) {
      return;
    }
    final src = localArticles[index];
    setState(() {
      final copy = src.copy()
        ..id = const Uuid().v4()
        ..name = '${src.name}_Kopie';
      localArticles.insert(index + 1, copy);
      _pendingAutofocusArticleId = copy.id;
      _expandedArticleId = copy.id;
    });
    _syncAllArticlePositionDisplays();
    _scrollArticleToTop(localArticles[index + 1].id);
    _scheduleClearPendingArticleAutofocus();
  }

  void _deleteArticleAt(int index) {
    if (localArticles.isEmpty || index < 0 || index >= localArticles.length) {
      return;
    }
    final sourceIndex = index;
    final removedId = localArticles[sourceIndex].id;
    setState(() {
      if (_expandedArticleId == removedId) {
        _expandedArticleId = null;
      }
      localArticles.removeAt(sourceIndex);
    });
    _articlePosControllers.remove(removedId)?.dispose();
    _articlePosFocusNodes.remove(removedId)?.dispose();
    _syncAllArticlePositionDisplays();
  }

  Future<void> _confirmDeleteAllArticles() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sicherheitsabfrage'),
        content: const Text(
          'Sind Sie wirklich sicher dass Sie alle Artikel loeschen moechten?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbruch'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ja, loeschen'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    setState(() {
      localArticles.clear();
      _expandedArticleId = null;
      _pendingAutofocusArticleId = null;
    });
    for (final c in _articlePosControllers.values) {
      c.dispose();
    }
    _articlePosControllers.clear();
    for (final f in _articlePosFocusNodes.values) {
      f.dispose();
    }
    _articlePosFocusNodes.clear();
    _articleTileKeys.clear();
  }

  void _scrollToGroupIndex(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_groupScrollController.hasClients) {
        return;
      }
      final target = (index * 84).toDouble();
      final max = _groupScrollController.position.maxScrollExtent;
      _groupScrollController.animateTo(
        target.clamp(0, max),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollGroupsToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_groupScrollController.hasClients) {
        return;
      }
      final max = _groupScrollController.position.maxScrollExtent;
      _groupScrollController.jumpTo(max);
    });
  }

  void _scrollArticlesToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_articleScrollController.hasClients) {
        return;
      }
      final max = _articleScrollController.position.maxScrollExtent;
      _articleScrollController.jumpTo(max);
    });
  }

  void _scrollArticleToTop(String articleId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final key = _articleTileKeys[articleId];
      final ctx = key?.currentContext;
      if (ctx == null) {
        return;
      }
      final ro = ctx.findRenderObject();
      if (ro == null || !ro.attached) {
        return;
      }
      try {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } catch (_) {
        return;
      }
    });
  }

  Future<void> _confirmDeleteAllReceipts() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Bist du dir sicher?'),
        content: const Text(
          'Es werden geloescht:\n'
          '- alle offenen Belege\n'
          '- alle bezahlten Belege\n'
          '- alle stornierten Belege\n'
          '- alle zugehoerigen Umsatzzeilen\n'
          '- alle wartenden Beleg-Uploads',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbruch'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ja, loeschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.onDeleteAllReceipts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alle Belege wurden geloescht')),
        );
      }
    }
  }

  Future<void> _confirmDeleteRevenueData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Bist du dir sicher?'),
        content: const Text(
          'Es werden geloescht:\n'
          '- alle lokalen Umsatzdaten fuer Auswertungen\n'
          '(Artikel, Gruppen, Einstellungen und Belege bleiben erhalten)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbruch'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ja, loeschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.db.clearRevenueData();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Umsatzdaten geloescht')));
      }
    }
  }

  Future<void> _addCustomField() async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Neues Feld'),
        content: TextField(controller: c),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbruch'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      setState(() => localSettings.customFields.add(v));
    }
  }

  void _resetArticleExpansionForImport() {
    // Sonst kann ein fokussiertes Positionsfeld beim Austausch der Artikelliste
    // InheritedElement-/Focus-Teardown aus dem Tritt bringen (_dependents.isEmpty).
    FocusManager.instance.primaryFocus?.unfocus();
    _expandedArticleId = null;
    _pendingAutofocusArticleId = null;
  }

  /// Nach Austausch von [localArticles]: alte Positions-Controller erst im naechsten Frame
  /// entsorgen, damit gemountete [TextField]s (Tab „Artikel“) nicht auf disposed Controller zeigen.
  void _pruneArticleEditorStateAfterImport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final keep = localArticles.map((a) => a.id).toSet();
      for (final id in _articlePosControllers.keys.toList()) {
        if (!keep.contains(id)) {
          _articlePosControllers.remove(id)?.dispose();
        }
      }
      for (final id in _articlePosFocusNodes.keys.toList()) {
        if (!keep.contains(id)) {
          final node = _articlePosFocusNodes.remove(id);
          if (node != null) {
            node.unfocus(
              disposition: UnfocusDisposition.previouslyFocusedChild,
            );
            node.dispose();
          }
        }
      }
      _articleTileKeys.removeWhere((id, _) => !keep.contains(id));
      _syncAllArticlePositionDisplays();
    });
  }

  void _applyCatalogXlsxImport(
    CatalogXlsxImport data, {
    String? saveSupabaseUrl,
    String? saveSupabaseAnonKey,
    String? saveSupabaseStorageBucket,
    String? saveSupabaseStorageObjectPath,

    /// true: Excel-Katalog (Datei oder Supabase) — Gruppen/Artikel vollstaendig
    /// durch die Datei ersetzen; Einstellungen nur aus dem Blatt neu (sonst Defaults).
    bool replaceEntireCatalogFromDownload = false,
  }) {
    _resetArticleExpansionForImport();

    final byExcelId = <int, String>{};
    final newGroups = <ArticleGroup>[];
    for (final g in data.groupsOrdered) {
      final gr = ArticleGroup(id: const Uuid().v4(), name: g.name);
      newGroups.add(gr);
      byExcelId[g.excelId] = gr.id;
    }
    final newArticles = <Article>[];
    for (final row in data.articleRows) {
      final gid = byExcelId[row.groupExcelId];
      if (gid == null) {
        continue;
      }
      newArticles.add(
        Article(
          id: const Uuid().v4(),
          name: row.name,
          price: row.price,
          groupId: gid,
          weekdays: WeekdaySelection(Map<String, bool>.from(row.weekdays)),
          customFields: List<String>.from(row.customFields),
        ),
      );
    }
    setState(() {
      if (replaceEntireCatalogFromDownload) {
        // Vorherige Gruppen/Artikel ersetzen (keine Uebernahme alter IDs);
        // Einstellungen nur aus der Datei neu aufbauen (ohne Blatt: Defaults).
        localSettings = SettingsData.fromJson(
          Map<String, dynamic>.from(data.settingsPatch ?? {}),
        );
      } else if (data.settingsPatch != null && data.settingsPatch!.isNotEmpty) {
        localSettings = SettingsData.fromJson(data.settingsPatch!);
      }
      if (saveSupabaseUrl != null) {
        localSettings.supabaseUrl = saveSupabaseUrl;
      }
      if (saveSupabaseAnonKey != null) {
        localSettings.supabaseAnonKey = saveSupabaseAnonKey;
      }
      if (saveSupabaseStorageBucket != null) {
        localSettings.supabaseStorageBucket = saveSupabaseStorageBucket;
      }
      if (saveSupabaseStorageObjectPath != null) {
        localSettings.supabaseStorageObjectPath = saveSupabaseStorageObjectPath;
      }
      localGroups = newGroups;
      localArticles = newArticles;
    });
    _pruneArticleEditorStateAfterImport();
    _persistChangesInBackground();
  }

  bool _pickedFileLooksLikeXlsx(PlatformFile f) {
    final n = f.name.toLowerCase();
    if (n.endsWith('.xlsx')) {
      return true;
    }
    final b = f.bytes;
    if (b != null && b.length >= 2 && b[0] == 0x50 && b[1] == 0x4b) {
      return true;
    }
    return false;
  }

  Future<void> _exportCatalogXlsx() async {
    final payloadBytes = encodeCatalogXlsx(
      settings: localSettings.toJson(),
      groups: localGroups.map((e) => e.toJson()).toList(),
      articles: localArticles.map((e) => e.toJson()).toList(),
    );
    if (payloadBytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Export fehlgeschlagen.')));
      }
      return;
    }
    const name = 'vereins_kasse_katalog.xlsx';
    if (kIsWeb) {
      final xfile = XFile.fromData(
        Uint8List.fromList(payloadBytes),
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        name: name,
      );
      await SharePlus.instance.share(
        ShareParams(files: [xfile], subject: name),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Export: Excel-Katalog wurde zum Teilen angeboten.'),
          ),
        );
      }
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final filePath = p.join(dir.path, name);
    await writeBytesToPath(filePath, payloadBytes);
    await SharePlus.instance.share(
      ShareParams(text: 'Export Vereins-Kasse Pro', files: [XFile(filePath)]),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export erstellt: $filePath')));
    }
  }

  Future<void> _importData() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'xlsx'],
      allowMultiple: false,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return;
    }
    final f = picked.files.single;
    late Uint8List rawBytes;
    if (f.bytes != null) {
      rawBytes = f.bytes!;
    } else if (f.path != null && !kIsWeb) {
      rawBytes = await readBytesFromPath(f.path!);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datei konnte nicht gelesen werden.')),
        );
      }
      return;
    }
    try {
      if (_pickedFileLooksLikeXlsx(f)) {
        final data = decodeCatalogXlsx(rawBytes);
        _applyCatalogXlsxImport(data, replaceEntireCatalogFromDownload: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Import erfolgreich (Excel-Katalog).'),
            ),
          );
        }
        return;
      }
      final raw = utf8.decode(rawBytes);
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _resetArticleExpansionForImport();
      setState(() {
        localSettings = SettingsData.fromJson(
          map['settings'] as Map<String, dynamic>,
        );
        localGroups = ((map['groups'] ?? []) as List)
            .map((e) => ArticleGroup.fromJson(e as Map<String, dynamic>))
            .toList();
        localArticles = ((map['articles'] ?? []) as List)
            .map((e) => Article.fromJson(e as Map<String, dynamic>))
            .toList();
      });
      _pruneArticleEditorStateAfterImport();
      await _persistChangesInBackground();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Import erfolgreich (JSON). Daten wurden uebernommen.',
            ),
          ),
        );
      }
    } on CatalogXlsxException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Excel-Import: $e')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Import fehlgeschlagen: Datei nicht lesbar oder kein gueltiges JSON.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _showSupabaseCatalogDownloadDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SupabaseCatalogDownloadDialog(
        initialUrl: localSettings.supabaseUrl,
        initialKey: localSettings.supabaseAnonKey,
        initialBucket: localSettings.supabaseStorageBucket,
        initialObjectPath: localSettings.supabaseStorageObjectPath,
        onImported: (data, saveUrl, saveKey, saveBucket, saveObjectPath) {
          if (!mounted) {
            return;
          }
          _applyCatalogXlsxImport(
            data,
            saveSupabaseUrl: saveUrl,
            saveSupabaseAnonKey: saveKey,
            saveSupabaseStorageBucket: saveBucket,
            saveSupabaseStorageObjectPath: saveObjectPath,
            replaceEntireCatalogFromDownload: true,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Katalog von Supabase importiert.')),
          );
        },
      ),
    );
  }
}

/// Eigenes [State]: Controller-Lebensdauer = Route; kein dispose im aeusseren `finally`
/// (das konnte zu frueh laufen und Requests / Builds brachen).
class _SupabaseCatalogDownloadDialog extends StatefulWidget {
  const _SupabaseCatalogDownloadDialog({
    required this.initialUrl,
    required this.initialKey,
    required this.initialBucket,
    required this.initialObjectPath,
    required this.onImported,
  });

  final String initialUrl;
  final String initialKey;
  final String initialBucket;
  final String initialObjectPath;
  final void Function(
    CatalogXlsxImport data,
    String saveUrl,
    String saveKey,
    String saveBucket,
    String saveObjectPath,
  )
  onImported;

  @override
  State<_SupabaseCatalogDownloadDialog> createState() =>
      _SupabaseCatalogDownloadDialogState();
}

class _SupabaseCatalogDownloadDialogState
    extends State<_SupabaseCatalogDownloadDialog> {
  late final TextEditingController _urlC;
  late final TextEditingController _keyC;
  late final TextEditingController _bucketC;
  late final TextEditingController _pathC;

  bool _busy = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _urlC = TextEditingController(text: widget.initialUrl);
    _keyC = TextEditingController(text: widget.initialKey);
    _bucketC = TextEditingController(text: widget.initialBucket);
    _pathC = TextEditingController(text: widget.initialObjectPath);
  }

  @override
  void dispose() {
    _urlC.dispose();
    _keyC.dispose();
    _bucketC.dispose();
    _pathC.dispose();
    super.dispose();
  }

  Future<void> _onDownload() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final bytes = await downloadSupabaseStorageObject(
        supabaseUrl: _urlC.text,
        anonKey: _keyC.text,
        bucket: _bucketC.text,
        objectPath: _pathC.text,
      );
      final data = decodeCatalogXlsx(bytes);
      if (!mounted) {
        return;
      }
      final saveUrl = _urlC.text.trim();
      final saveKey = _keyC.text.trim();
      final saveBucket = _bucketC.text.trim();
      final savePath = _pathC.text.trim();
      Navigator.pop(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onImported(data, saveUrl, saveKey, saveBucket, savePath);
      });
    } on CatalogXlsxException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Download Daten (Supabase Storage)'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Bucket braucht Leserechte fuer den Anon-Key (z. B. oeffentlicher Bucket oder Policy). '
                'Pfad relativ zum Bucket, z. B. katalog/Fruehlingsfest.xlsx',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (_errorText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_errorText!, style: TextStyle(color: cs.error)),
                ),
              TextField(
                controller: _urlC,
                decoration: const InputDecoration(labelText: 'Supabase URL'),
                enabled: !_busy,
              ),
              TextField(
                controller: _keyC,
                decoration: const InputDecoration(
                  labelText: 'Supabase Anon Key',
                ),
                obscureText: true,
                enabled: !_busy,
              ),
              TextField(
                controller: _bucketC,
                decoration: const InputDecoration(labelText: 'Storage Bucket'),
                enabled: !_busy,
              ),
              TextField(
                controller: _pathC,
                decoration: const InputDecoration(
                  labelText: 'Dateipfad im Bucket',
                ),
                enabled: !_busy,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _busy ? null : _onDownload,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Herunterladen und importieren'),
        ),
      ],
    );
  }
}

class AppDatabase {
  Database? _db;
  Future<void> init() async {
    final String dbPath;
    if (kIsWeb) {
      dbPath = 'vereins_kasse.db';
    } else {
      final base = await getDatabasesPath();
      dbPath = p.join(base, 'vereins_kasse.db');
    }
    _db = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE settings (k TEXT PRIMARY KEY, v TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE groups (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE articles (id TEXT PRIMARY KEY, name TEXT NOT NULL, price REAL NOT NULL, group_id TEXT NOT NULL, weekdays_json TEXT NOT NULL, custom_fields_json TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE completed_rows (id TEXT PRIMARY KEY, invoice_number INTEGER NOT NULL, group_name TEXT NOT NULL, article_name TEXT NOT NULL, quantity INTEGER NOT NULL, unit_price REAL NOT NULL, total_price REAL NOT NULL, ts TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE completed_invoices (id TEXT PRIMARY KEY, invoice_number INTEGER NOT NULL, tip_amount REAL NOT NULL, ts TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE upload_queue (id TEXT PRIMARY KEY, payload_json TEXT NOT NULL, done INTEGER NOT NULL DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE session_snapshot (id INTEGER PRIMARY KEY CHECK (id = 1), payload_json TEXT NOT NULL)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS completed_invoices (id TEXT PRIMARY KEY, invoice_number INTEGER NOT NULL, tip_amount REAL NOT NULL, ts TEXT NOT NULL)',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS session_snapshot (id INTEGER PRIMARY KEY CHECK (id = 1), payload_json TEXT NOT NULL)',
          );
        }
      },
    );
  }

  Database get db => _db!;

  Future<void> saveSessionSnapshot(String json) async {
    await db.insert('session_snapshot', {
      'id': 1,
      'payload_json': json,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> loadSessionSnapshot() async {
    final rows = await db.query(
      'session_snapshot',
      where: 'id = ?',
      whereArgs: [1],
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['payload_json'] as String?;
  }

  Future<void> clearSessionSnapshot() async {
    await db.delete('session_snapshot', where: 'id = ?', whereArgs: [1]);
  }

  Future<SettingsData> loadSettings() async {
    final rows = await db.query('settings');
    if (rows.isEmpty) {
      return SettingsData.defaultValues();
    }
    final map = <String, dynamic>{};
    for (final r in rows) {
      map[r['k'] as String] = jsonDecode(r['v'] as String);
    }
    return SettingsData.fromJson(map);
  }

  Future<void> saveSettings(SettingsData settings) async {
    await db.delete('settings');
    for (final e in settings.toJson().entries) {
      await db.insert('settings', {'k': e.key, 'v': jsonEncode(e.value)});
    }
  }

  Future<List<ArticleGroup>> loadGroups() async {
    final rows = await db.query('groups');
    return rows
        .map(
          (e) => ArticleGroup(id: e['id'] as String, name: e['name'] as String),
        )
        .toList();
  }

  Future<void> upsertGroup(ArticleGroup g) async {
    await db.insert(
      'groups',
      g.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> replaceGroups(List<ArticleGroup> groups) async {
    await db.transaction((txn) async {
      await txn.delete('groups');
      for (final g in groups) {
        await txn.insert(
          'groups',
          g.toJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<Article>> loadArticles() async {
    final rows = await db.query('articles');
    return rows
        .map(
          (r) => Article(
            id: r['id'] as String,
            name: r['name'] as String,
            price: _coerceToDouble(r['price']),
            groupId: r['group_id'] as String,
            weekdays: WeekdaySelection.fromJson(
              jsonDecode(r['weekdays_json'] as String) as Map<String, dynamic>,
            ),
            customFields:
                ((jsonDecode(r['custom_fields_json'] as String)) as List)
                    .cast<String>(),
          ),
        )
        .toList();
  }

  Future<void> upsertArticle(Article a) async {
    await db.insert(
      'articles',
      a.toDbJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> replaceArticles(List<Article> articles) async {
    await db.transaction((txn) async {
      await txn.delete('articles');
      for (final a in articles) {
        await txn.insert(
          'articles',
          a.toDbJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> insertCompletedInvoice(Invoice inv) async {
    for (final i in inv.items) {
      await db.insert('completed_rows', {
        'id': const Uuid().v4(),
        'invoice_number': inv.number,
        'group_name': i.groupName,
        'article_name': i.articleName,
        'quantity': i.quantity,
        'unit_price': i.unitPrice,
        'total_price': i.lineTotal,
        'ts': (inv.paidAt ?? DateTime.now()).toIso8601String(),
      });
    }
  }

  Future<void> insertCompletedInvoiceSummary(Invoice inv) async {
    await db.insert('completed_invoices', {
      'id': const Uuid().v4(),
      'invoice_number': inv.number,
      'tip_amount': inv.tipAmount,
      'ts': (inv.paidAt ?? DateTime.now()).toIso8601String(),
    });
  }

  Future<List<CompletedRow>> loadCompletedInvoiceRows() async {
    final rows = await db.query('completed_rows');
    return rows
        .map(
          (r) => CompletedRow(
            groupName: (r['group_name'] as String?) ?? '',
            articleName: (r['article_name'] as String?) ?? '',
            quantity: _coerceToInt(r['quantity'], defaultValue: 1),
            unitPrice: _coerceToDouble(r['unit_price']),
            totalPrice: _coerceToDouble(r['total_price']),
          ),
        )
        .toList();
  }

  Future<String> enqueueUpload(List<Map<String, dynamic>> payload) async {
    final id = const Uuid().v4();
    await db.insert('upload_queue', {
      'id': id,
      'payload_json': jsonEncode(payload),
      'done': 0,
    });
    return id;
  }

  Future<List<UploadQueueItem>> loadUploadQueue() async {
    final rows = await db.query('upload_queue', where: 'done = 0');
    return rows
        .map(
          (r) => UploadQueueItem(
            id: r['id'] as String,
            payload: ((jsonDecode(r['payload_json'] as String)) as List)
                .map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v)))
                .toList(),
          ),
        )
        .toList();
  }

  Future<int> countPendingUploads() async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM upload_queue WHERE done = 0',
    );
    if (rows.isEmpty) {
      return 0;
    }
    final v = rows.first['c'];
    if (v is int) {
      return v;
    }
    if (v is num) {
      return v.toInt();
    }
    return 0;
  }

  Future<void> markQueueDone(String id) async {
    await db.update(
      'upload_queue',
      {'done': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearRevenueData() async {
    await db.delete('completed_rows');
    await db.delete('completed_invoices');
  }

  Future<void> clearAllData() async {
    await db.transaction((txn) async {
      await txn.delete('settings');
      await txn.delete('groups');
      await txn.delete('articles');
      await txn.delete('completed_rows');
      await txn.delete('completed_invoices');
      await txn.delete('upload_queue');
      await txn.delete('session_snapshot');
    });
  }

  Future<void> clearAllReceiptsData() async {
    await db.transaction((txn) async {
      await txn.delete('completed_rows');
      await txn.delete('completed_invoices');
      await txn.delete('upload_queue');
      await txn.delete('session_snapshot');
    });
  }

  Future<double> loadTotalTips() async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(tip_amount), 0) AS total FROM completed_invoices',
    );
    final value = rows.isNotEmpty ? rows.first['total'] : 0;
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    return double.tryParse(value?.toString() ?? '0') ?? 0;
  }
}

class SupabaseUploader {
  Future<bool> tryUpload({
    required SettingsData settings,
    required List<Map<String, dynamic>> payload,
  }) async {
    if (settings.supabaseUrl.isEmpty || settings.supabaseAnonKey.isEmpty) {
      return false;
    }
    try {
      final client = SupabaseClient(
        settings.supabaseUrl,
        settings.supabaseAnonKey,
      );
      await client.from('sales').insert(payload);
      return true;
    } catch (_) {
      return false;
    }
  }
}

class SettingsData {
  SettingsData({
    required this.dayEnabled,
    required this.customFields,
    required this.presetTableNumbers,
    required this.receiptPaneWidth,
    required this.articleColumns,
    required this.articleTileWidth,
    required this.articleTileHeight,
    this.articleTileGap = 8,
    required int articleGroupRows,
    required this.showPriceOnTiles,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    String supabaseStorageBucket = '',
    String supabaseStorageObjectPath = '',
    bool? uploadSalesToSupabase,
    this.receiptUiScale = 1.0,
    this.articleUiScale = 1.0,
    this.batteryDarkMode = true,
    this.articleCatalogSeedVersion = 0,
  }) : _articleGroupRows = articleGroupRows.clamp(1, 3),
       _uploadSalesToSupabase = uploadSalesToSupabase,
       _supabaseStorageBucket = supabaseStorageBucket,
       _supabaseStorageObjectPath = supabaseStorageObjectPath;

  Map<String, bool> dayEnabled;
  List<String> customFields;

  /// Schnellauswahl fuer Name/Tisch im Beleg.
  List<String> presetTableNumbers;
  double receiptPaneWidth;
  int articleColumns;
  double articleTileWidth;
  double articleTileHeight;
  double articleTileGap;
  int? _articleGroupRows;
  int get articleGroupRows => (_articleGroupRows ?? 1).clamp(1, 3);
  set articleGroupRows(int v) {
    _articleGroupRows = v.clamp(1, 3);
  }

  /// Skalierung Schrift/Buttons im Belegbereich (0.55–1.0).
  double receiptUiScale;

  /// Skalierung Schrift/Labels bei Artikelkacheln und Gruppenleiste.
  double articleUiScale;
  bool batteryDarkMode;
  bool showPriceOnTiles;
  String supabaseUrl;
  String supabaseAnonKey;

  String? _supabaseStorageBucket;
  String? _supabaseStorageObjectPath;

  /// Zuletzt verwendeter Storage-Bucket fuer Katalog-Download (App merkt sich die Eingabe).
  String get supabaseStorageBucket => _supabaseStorageBucket ?? '';

  /// Objektpfad innerhalb des Buckets, z. B. katalog/Datei.xlsx
  String get supabaseStorageObjectPath => _supabaseStorageObjectPath ?? '';

  set supabaseStorageBucket(String v) => _supabaseStorageBucket = v;

  set supabaseStorageObjectPath(String v) => _supabaseStorageObjectPath = v;

  /// Intern null nach Hot Reload / alter Sessions — Getter liefert dann true.
  bool? _uploadSalesToSupabase;

  /// Wenn true (Standard): Bar-Zahlung nur moeglich, wenn Supabase URL/Key gesetzt; sonst Kassen-Dialog blockiert.
  bool get uploadSalesToSupabase => _uploadSalesToSupabase ?? true;

  set uploadSalesToSupabase(bool v) => _uploadSalesToSupabase = v;

  /// Erhoehen in [kArticleCatalogSeedVersion], um Fruehlingsfest-Artikelkatalog erneut einzuspielen.
  int articleCatalogSeedVersion;

  List<String> get availableWorkdays {
    final week = WeekdaySelection.dayCodes
        .where((d) => dayEnabled[d] ?? true)
        .toList();
    final all = [...week, ...customFields];
    if (all.isEmpty) {
      return ['Mo'];
    }
    return all;
  }

  static SettingsData defaultValues() => SettingsData(
    dayEnabled: {
      'Mo': true,
      'Di': true,
      'Mi': true,
      'Do': true,
      'Fr': true,
      'Sa': true,
      'So': true,
    },
    customFields: [],
    presetTableNumbers: [],
    receiptPaneWidth: 160,
    articleColumns: 2,
    articleTileWidth: 1.2,
    articleTileHeight: 0.9,
    articleTileGap: 8,
    articleGroupRows: 1,
    receiptUiScale: 0.8,
    articleUiScale: 0.85,
    batteryDarkMode: true,
    showPriceOnTiles: true,
    supabaseUrl: '',
    supabaseAnonKey: '',
    supabaseStorageBucket: '',
    supabaseStorageObjectPath: '',
    uploadSalesToSupabase: true, // explizit, nicht null
    articleCatalogSeedVersion: 0,
  );

  SettingsData copy() => SettingsData.fromJson(toJson());
  Map<String, dynamic> toJson() => {
    'dayEnabled': dayEnabled,
    'customFields': customFields,
    'presetTableNumbers': presetTableNumbers,
    'receiptPaneWidth': receiptPaneWidth,
    'articleColumns': articleColumns,
    'articleTileWidth': articleTileWidth,
    'articleTileHeight': articleTileHeight,
    'articleTileGap': articleTileGap,
    'articleGroupRows': articleGroupRows,
    'receiptUiScale': receiptUiScale,
    'articleUiScale': articleUiScale,
    'batteryDarkMode': batteryDarkMode,
    'showPriceOnTiles': showPriceOnTiles,
    'supabaseUrl': supabaseUrl,
    'supabaseAnonKey': supabaseAnonKey,
    'supabaseStorageBucket': supabaseStorageBucket,
    'supabaseStorageObjectPath': supabaseStorageObjectPath,
    'uploadSalesToSupabase': _uploadSalesToSupabase ?? true,
    'articleCatalogSeedVersion': articleCatalogSeedVersion,
  };

  /// Gespeicherte Werte aus DB/JSON werden mit [defaultValues] zusammengefuehrt,
  /// damit neue Installations-Standards gelten, sobald ein Schluessel fehlt.
  factory SettingsData.fromJson(Map<String, dynamic> json) {
    final d = SettingsData.defaultValues();
    final merged = Map<String, dynamic>.from(d.toJson());
    merged.addAll(json);
    return SettingsData(
      dayEnabled: ((merged['dayEnabled'] ?? {}) as Map).map(
        (k, v) => MapEntry(k.toString(), v == true),
      ),
      customFields: ((merged['customFields'] ?? []) as List).cast<String>(),
      presetTableNumbers: ((merged['presetTableNumbers'] ?? []) as List)
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList(),
      receiptPaneWidth: _coerceToDouble(
        merged['receiptPaneWidth'],
        defaultValue: d.receiptPaneWidth,
      ),
      articleColumns: _coerceToInt(
        merged['articleColumns'],
        defaultValue: d.articleColumns,
      ),
      articleTileWidth: _coerceToDouble(
        merged['articleTileWidth'],
        defaultValue: d.articleTileWidth,
      ),
      articleTileHeight: _coerceToDouble(
        merged['articleTileHeight'],
        defaultValue: d.articleTileHeight,
      ),
      articleTileGap: _coerceToDouble(
        merged['articleTileGap'],
        defaultValue: d.articleTileGap,
      ).clamp(0, 24),
      articleGroupRows: _coerceToInt(
        merged['articleGroupRows'],
        defaultValue: d.articleGroupRows,
      ).clamp(1, 3),
      receiptUiScale: _coerceToDouble(
        merged['receiptUiScale'],
        defaultValue: d.receiptUiScale,
      ),
      articleUiScale: _coerceToDouble(
        merged['articleUiScale'],
        defaultValue: d.articleUiScale,
      ),
      batteryDarkMode: merged['batteryDarkMode'] == true,
      showPriceOnTiles: merged['showPriceOnTiles'] != false,
      supabaseUrl: (merged['supabaseUrl'] ?? '').toString(),
      supabaseAnonKey: (merged['supabaseAnonKey'] ?? '').toString(),
      supabaseStorageBucket: _settingsJsonString(
        merged['supabaseStorageBucket'],
      ),
      supabaseStorageObjectPath: _settingsJsonString(
        merged['supabaseStorageObjectPath'],
      ),
      uploadSalesToSupabase: _parseUploadSalesFlag(
        merged['uploadSalesToSupabase'],
      ),
      articleCatalogSeedVersion: _coerceToInt(
        merged['articleCatalogSeedVersion'],
        defaultValue: d.articleCatalogSeedVersion,
      ),
    );
  }
}

class WeekdaySelection {
  WeekdaySelection(this.values);
  final Map<String, bool> values;
  static const dayCodes = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  static WeekdaySelection all() =>
      WeekdaySelection({for (final d in dayCodes) d: true});
  bool isDayEnabled(String day) => values[day] ?? false;
  Map<String, dynamic> toJson() => values;
  factory WeekdaySelection.fromJson(Map<String, dynamic> map) =>
      WeekdaySelection(map.map((k, v) => MapEntry(k, v == true)));
}

class ArticleGroup {
  ArticleGroup({required this.id, required this.name});
  String id;
  String name;
  ArticleGroup copy() => ArticleGroup(id: id, name: name);
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory ArticleGroup.fromJson(Map<String, dynamic> json) =>
      ArticleGroup(id: json['id'] as String, name: json['name'] as String);
}

class Article {
  Article({
    required this.id,
    required this.name,
    required this.price,
    required this.groupId,
    required this.weekdays,
    required this.customFields,
  });
  String id;
  String name;
  double price;
  String groupId;
  WeekdaySelection weekdays;
  List<String> customFields;

  Article copy() => Article(
    id: id,
    name: name,
    price: price,
    groupId: groupId,
    weekdays: WeekdaySelection.fromJson(weekdays.toJson()),
    customFields: List.of(customFields),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'groupId': groupId,
    'weekdays': weekdays.toJson(),
    'customFields': customFields,
  };

  Map<String, dynamic> toDbJson() => {
    'id': id,
    'name': name,
    'price': price,
    'group_id': groupId,
    'weekdays_json': jsonEncode(weekdays.toJson()),
    'custom_fields_json': jsonEncode(customFields),
  };

  factory Article.fromJson(Map<String, dynamic> json) => Article(
    id: json['id'] as String,
    name: json['name'] as String,
    price: (json['price']).toDouble(),
    groupId: json['groupId'] as String,
    weekdays: WeekdaySelection.fromJson(
      (json['weekdays'] as Map).cast<String, dynamic>(),
    ),
    customFields: ((json['customFields'] ?? []) as List).cast<String>(),
  );
}

class Invoice {
  Invoice({
    required this.number,
    required this.createdAt,
    required this.items,
    required this.nameOrTable,
    required this.isPaid,
    required this.isCancelled,
    required this.tipAmount,
    this.paidAt,
    this.workday = '',
  });

  final int number;
  final DateTime createdAt;
  final List<InvoiceItem> items;
  String nameOrTable;
  bool isPaid;
  bool isCancelled;
  double tipAmount;
  DateTime? paidAt;
  String workday;

  factory Invoice.next({required int number}) => Invoice(
    number: number,
    createdAt: DateTime.now(),
    items: [],
    nameOrTable: '',
    isPaid: false,
    isCancelled: false,
    tipAmount: 0,
  );

  bool get isEmpty => items.isEmpty;
  double get total => items.fold(0, (s, e) => s + e.lineTotal);

  void addArticle(Article article) {
    final existing = items.where((e) => e.articleId == article.id).firstOrNull;
    if (existing != null) {
      existing.quantity += 1;
      return;
    }
    items.add(
      InvoiceItem(
        articleId: article.id,
        articleName: article.name,
        unitPrice: article.price,
        quantity: 1,
        groupName: '',
      ),
    );
  }

  void addInvoiceItem(InvoiceItem item) {
    final existing = items
        .where((e) => e.articleId == item.articleId)
        .firstOrNull;
    if (existing != null) {
      existing.quantity += item.quantity;
      return;
    }
    items.add(item);
  }

  Invoice copy() => Invoice(
    number: number,
    createdAt: createdAt,
    items: items.map((e) => e.copy()).toList(),
    nameOrTable: nameOrTable,
    isPaid: isPaid,
    isCancelled: isCancelled,
    tipAmount: tipAmount,
    paidAt: paidAt,
    workday: workday,
  );

  Map<String, dynamic> toJson() => {
    'number': number,
    'createdAt': createdAt.toIso8601String(),
    'nameOrTable': nameOrTable,
    'isPaid': isPaid,
    'isCancelled': isCancelled,
    'tipAmount': tipAmount,
    'paidAt': paidAt?.toIso8601String(),
    'workday': workday,
    'items': items.map((e) => e.toJson()).toList(),
  };

  factory Invoice.fromJson(Map<String, dynamic> json) {
    final paidRaw = json['paidAt'];
    return Invoice(
      number: _coerceToInt(json['number'], defaultValue: 1),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      items: ((json['items'] ?? []) as List)
          .map((e) => InvoiceItem.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      nameOrTable: (json['nameOrTable'] ?? '').toString(),
      isPaid: json['isPaid'] == true,
      isCancelled: json['isCancelled'] == true,
      tipAmount: _coerceToDouble(json['tipAmount']),
      paidAt: paidRaw == null || paidRaw.toString().isEmpty
          ? null
          : DateTime.tryParse(paidRaw.toString()),
      workday: (json['workday'] ?? '').toString(),
    );
  }

  List<Map<String, dynamic>> toSalesPayload() {
    final ts = (paidAt ?? DateTime.now()).toIso8601String();
    return items
        .map(
          (i) => {
            'group_name': i.groupName,
            'article': i.articleName,
            'quantity': i.quantity,
            'unit_price': i.unitPrice,
            'total_price': i.lineTotal,
            'workday': workday,
            'sold_at': ts,
            'invoice_number': number,
            'table_name': nameOrTable,
          },
        )
        .toList();
  }
}

class InvoiceItem {
  InvoiceItem({
    required this.articleId,
    required this.articleName,
    required this.unitPrice,
    required this.quantity,
    required this.groupName,
  });
  final String articleId;
  final String articleName;
  final double unitPrice;
  int quantity;
  final String groupName;
  double get lineTotal => unitPrice * quantity;
  InvoiceItem copy() => InvoiceItem(
    articleId: articleId,
    articleName: articleName,
    unitPrice: unitPrice,
    quantity: quantity,
    groupName: groupName,
  );

  Map<String, dynamic> toJson() => {
    'articleId': articleId,
    'articleName': articleName,
    'unitPrice': unitPrice,
    'quantity': quantity,
    'groupName': groupName,
  };

  factory InvoiceItem.fromJson(Map<String, dynamic> json) => InvoiceItem(
    articleId: (json['articleId'] ?? '').toString(),
    articleName: (json['articleName'] ?? '').toString(),
    unitPrice: _coerceToDouble(json['unitPrice']),
    quantity: _coerceToInt(json['quantity'], defaultValue: 1),
    groupName: (json['groupName'] ?? '').toString(),
  );
}

class CompletedRow {
  CompletedRow({
    required this.groupName,
    required this.articleName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });
  final String groupName;
  final String articleName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
}

class UploadQueueItem {
  UploadQueueItem({required this.id, required this.payload});
  final String id;
  final List<Map<String, dynamic>> payload;
}

class CashResult {
  CashResult({required this.paidCash, required this.roundTo});
  final bool paidCash;
  final double roundTo;
}
