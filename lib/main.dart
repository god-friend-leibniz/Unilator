import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:translator/translator.dart';
import 'dictionary_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OfflineDictApp());
}

Future<void> _writeTask(Map<String, dynamic> args) async {
  final String filePath = args['path'];
  final Uint8List bytes = args['bytes'];
  final file = File(filePath);
  await file.writeAsBytes(bytes, flush: true);
}

class DictInstance {
  final String name;
  final DictionaryEngine engine;
  final bool isTranslationDict;

  DictInstance({
    required this.name,
    required this.engine,
    this.isTranslationDict = false,
  });
}

class TranslationService {
  final OnDeviceTranslator _onDeviceTranslator = OnDeviceTranslator(
    sourceLanguage: TranslateLanguage.english,
    targetLanguage: TranslateLanguage.russian,
  );

  Future<Map<String, String>> translate(String text) async {
    bool isOnline = false;

    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 2));
      isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      isOnline = false;
    }

    if (isOnline) {
      try {
        final translator = GoogleTranslator();
        final translation = await translator.translate(
          text,
          from: 'en',
          to: 'ru',
        );
        return {'text': translation.text, 'source': 'Онлайн (Google)'};
      } catch (e) {
        debugPrint("Google API failed: $e");
      }
    }

    try {
      final offlineTranslation = await _onDeviceTranslator.translateText(text);
      return {'text': offlineTranslation, 'source': 'Оффлайн (ML Kit)'};
    } catch (e) {
      return {'text': 'Ошибка локальной модели', 'source': 'Ошибка'};
    }
  }

  void dispose() {
    _onDeviceTranslator.close();
  }
}

class OfflineDictApp extends StatelessWidget {
  const OfflineDictApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Dictionary',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyanAccent,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const DictionaryScreen(),
    );
  }
}

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final List<DictInstance> _engines = [];
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TranslationService _translationService = TranslationService();

  final List<String> _translationDictKeywords = [
    'muller',
    'mueller',
    'macmillan',
    'ru',
  ];

  List<Map<String, dynamic>> _englishBlocks = [];
  List<Map<String, dynamic>> _translationBlocks = [];

  String _translatedQueryText = "";

  bool _hasSearched = false;
  bool _isInitializing = true;

  bool _isTranslated = false;
  bool _isTranslating = false;
  bool _isDeepSearchMode = false;

  String _lastTranslatedQuery = "";
  String _translationSource = "";

  int _loadedCount = 0;
  String _currentQuery = "";

  @override
  void initState() {
    super.initState();
    _startSetup();
  }

  @override
  void dispose() {
    _translationService.dispose();
    super.dispose();
  }

  String _formatDictName(String rawName) {
    return rawName.replaceAll('_clean', '').replaceAll('_', ' ').toUpperCase();
  }

  Future<void> _startSetup() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final AssetManifest manifest = await AssetManifest.loadFromAssetBundle(
        rootBundle,
      );
      final List<String> allAssets = manifest.listAssets();

      final idxAssets = allAssets
          .where(
            (String key) =>
                key.startsWith('assets/clean/') && key.endsWith('.idx'),
          )
          .toList();

      int count = 0;

      for (final idxAssetPath in idxAssets) {
        final fileName = path.basename(idxAssetPath);
        final baseName = fileName.substring(0, fileName.length - 4);
        final dictAssetPath = 'assets/clean/$baseName.dict';

        final localIdxPath = path.join(dir.path, fileName);
        final localDictPath = path.join(dir.path, '$baseName.dict');

        try {
          if (!await File(localIdxPath).exists()) {
            final idxData = await rootBundle.load(idxAssetPath);
            await compute(_writeTask, {
              'path': localIdxPath,
              'bytes': idxData.buffer.asUint8List(),
            });
          }
          if (!await File(localDictPath).exists() &&
              allAssets.contains(dictAssetPath)) {
            final dictData = await rootBundle.load(dictAssetPath);
            await compute(_writeTask, {
              'path': localDictPath,
              'bytes': dictData.buffer.asUint8List(),
            });
          }
        } catch (e) {
          debugPrint('Ошибка копирования словаря $baseName: $e');
        }

        if (File(localIdxPath).existsSync() &&
            File(localDictPath).existsSync()) {
          final engine = DictionaryEngine();
          if (await engine.load(localIdxPath, localDictPath)) {
            // Определяем, является ли этот словарь русским/переводным по массиву
            final lowerName = baseName.toLowerCase();
            final isTranslationDict = _translationDictKeywords.any(
              (keyword) => lowerName.contains(keyword),
            );

            _engines.add(
              DictInstance(
                name: _formatDictName(baseName),
                engine: engine,
                isTranslationDict: isTranslationDict,
              ),
            );
            count++;
          }
        }
      }

      if (mounted) {
        setState(() {
          _isInitializing = false;
          _loadedCount = count;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isInitializing = false);
      debugPrint('Ошибка инициализации: $e');
    }
  }

  void _performSearch(String query) {
    query = query.trim();
    if (_engines.isEmpty || query.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();

    _isTranslated = false;
    _translatedQueryText = "";

    final queryWords = query.split(RegExp(r'\s+'));
    final firstWord = queryWords.first.toLowerCase();
    final isComplexSearch = queryWords.length > 1;
    final fullPhrase = query.toLowerCase();

    List<Map<String, dynamic>> englishResults = [];
    List<Map<String, dynamic>> translationResults = [];

    for (var dict in _engines) {
      // Выбираем, в какой список попадут результаты этого словаря
      final targetList = dict.isTranslationDict
          ? translationResults
          : englishResults;
      final startIndex = targetList.length;

      bool hasTitle = false;
      final engine = dict.engine;
      final dictName = dict.name;
      Set<String> seenTexts = {};

      void addBlocks(String jsonStr, bool filterByPhrase) {
        if (jsonStr.isEmpty) return;
        try {
          List<dynamic> blocks = jsonDecode(jsonStr);
          if (blocks.isEmpty) return;

          bool inMatchingSection = false;

          for (var block in blocks) {
            final type = block['t'] as String;
            final text = block['v'] as String;

            if (text.toLowerCase().contains('.wav') ||
                text.toLowerCase().contains('.jpg') ||
                text.trim().isEmpty) {
              continue;
            }

            if (!filterByPhrase) {
              if (!seenTexts.contains('${type}_$text')) {
                seenTexts.add('${type}_$text');
                if (!hasTitle) {
                  targetList.add({"t": "dict_title", "v": dictName});
                  hasTitle = true;
                }
                targetList.add({"t": type, "v": text});
              }
            } else {
              if (type == 'h') {
                inMatchingSection = text.toLowerCase().contains(fullPhrase);
                if (inMatchingSection) {
                  if (!seenTexts.contains('${type}_$text')) {
                    seenTexts.add('${type}_$text');
                    if (!hasTitle) {
                      targetList.add({"t": "dict_title", "v": dictName});
                      hasTitle = true;
                    }
                    targetList.add({"t": type, "v": text, "highlight": query});
                  }
                }
              } else {
                if (inMatchingSection ||
                    text.toLowerCase().contains(fullPhrase)) {
                  if (!seenTexts.contains('${type}_$text')) {
                    seenTexts.add('${type}_$text');
                    if (!hasTitle) {
                      targetList.add({"t": "dict_title", "v": dictName});
                      hasTitle = true;
                    }
                    targetList.add({"t": type, "v": text, "highlight": query});
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('JSON Decode Error: $e');
        }
      }

      if (!isComplexSearch) {
        addBlocks(engine.translate(fullPhrase), false);
      } else {
        if (!_isDeepSearchMode) {
          addBlocks(engine.translate(fullPhrase), false);
        } else {
          addBlocks(engine.translate(fullPhrase), false);
          addBlocks(engine.translate(firstWord), true);
        }
      }

      if (targetList.length > startIndex) {
        bool hasMeaningfulContent = false;
        for (int i = startIndex; i < targetList.length; i++) {
          final t = targetList[i]['t'];
          if (t != 'dict_title' && t != 'h') {
            hasMeaningfulContent = true;
            break;
          }
        }
        if (!hasMeaningfulContent) {
          targetList.add({"t": "empty_state", "v": "Толкование отсутствует"});
        }
      }
    }

    setState(() {
      _hasSearched = true;
      _currentQuery = query;
      _englishBlocks = englishResults;
      _translationBlocks = translationResults;
    });

    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _toggleTranslation() async {
    if (_isTranslated) {
      setState(() => _isTranslated = false);
      return;
    }

    if (_translatedQueryText.isNotEmpty &&
        _lastTranslatedQuery == _currentQuery) {
      setState(() => _isTranslated = true);
      return;
    }

    setState(() {
      _isTranslating = true;
    });

    try {
      final result = await _translationService.translate(_currentQuery);

      if (mounted) {
        setState(() {
          _translatedQueryText = result['text']!;
          _translationSource = result['source']!;
          _isTranslated = true;
          _lastTranslatedQuery = _currentQuery;
          _isTranslating = false;
        });
      }
    } catch (e) {
      debugPrint("Translation Error: $e");
      if (mounted) {
        setState(() => _isTranslating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Критическая ошибка перевода.')),
        );
      }
    }
  }

  Widget _buildBlockWidget(
    Map<String, dynamic> block,
    ThemeData theme,
    bool isDark,
  ) {
    final type = block['t'] as String;
    final text = block['v'] as String;
    final highlight = block['highlight'] as String?;

    TextStyle baseStyle;
    EdgeInsets padding = const EdgeInsets.only(bottom: 8.0);
    String displayText = text;

    switch (type) {
      case 'h':
        final isMainWord =
            text.toLowerCase() == _currentQuery.toLowerCase() ||
            text.toLowerCase() ==
                _currentQuery.split(RegExp(r'\s+')).first.toLowerCase();

        baseStyle = TextStyle(
          fontSize: isMainWord ? 28 : 20,
          fontWeight: isMainWord ? FontWeight.w800 : FontWeight.bold,
          color: isMainWord
              ? (isDark ? Colors.cyanAccent : theme.colorScheme.primary)
              : (isDark ? Colors.amberAccent[200] : Colors.orange[800]),
        );
        padding = EdgeInsets.only(top: isMainWord ? 12.0 : 12.0, bottom: 8.0);
        break;

      case 'ex':
        baseStyle = TextStyle(
          fontSize: 18,
          fontStyle: FontStyle.italic,
          color: isDark ? Colors.greenAccent : Colors.green[700],
        );
        padding = const EdgeInsets.only(left: 16.0, bottom: 8.0);
        displayText = '• $text';
        break;

      case 'gram':
        baseStyle = TextStyle(
          fontSize: 16,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.lightBlueAccent : Colors.blueGrey[700],
        );
        break;

      case 'dict_title':
        return Padding(
          padding: const EdgeInsets.only(top: 24.0, bottom: 12.0),
          child: Row(
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 18,
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: theme.colorScheme.primary.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Divider(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  thickness: 1,
                ),
              ),
            ],
          ),
        );

      case 'empty_state':
        baseStyle = TextStyle(
          fontSize: 16,
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        );
        padding = const EdgeInsets.only(left: 16.0, bottom: 16.0, top: 8.0);
        break;

      case 'def':
      default:
        baseStyle = TextStyle(
          fontSize: 18,
          color: isDark ? Colors.white : Colors.black87,
        );
        break;
    }

    if (highlight != null && highlight.isNotEmpty) {
      return Padding(
        padding: padding,
        child: _highlightText(displayText, highlight, baseStyle),
      );
    } else {
      return Padding(
        padding: padding,
        child: Text(displayText, style: baseStyle),
      );
    }
  }

  Widget _highlightText(String text, String highlight, TextStyle baseStyle) {
    final spans = <TextSpan>[];
    int start = 0;
    final lowerText = text.toLowerCase();
    final lowerHighlight = highlight.toLowerCase();
    int idx = lowerText.indexOf(lowerHighlight, start);

    final highlightStyle = baseStyle.copyWith(
      fontWeight: FontWeight.bold,
      fontStyle: FontStyle.normal,
    );

    while (idx != -1) {
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: baseStyle));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + highlight.length),
          style: highlightStyle,
        ),
      );
      start = idx + highlight.length;
      idx = lowerText.indexOf(lowerHighlight, start);
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }

    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final blocksToRender = _isTranslated ? _translationBlocks : _englishBlocks;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Оффлайн Словари',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E1E1E)
                        : theme.colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Введите слово или фразу...',
                      prefixIcon: Icon(
                        Icons.search,
                        color: theme.colorScheme.primary,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isTranslating)
                            Padding(
                              padding: const EdgeInsets.only(right: 12.0),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            )
                          else if (_hasSearched) ...[
                            if (_currentQuery.trim().contains(' '))
                              IconButton(
                                icon: Icon(
                                  Icons.find_in_page,
                                  color: _isDeepSearchMode
                                      ? (isDark
                                            ? Colors.cyanAccent
                                            : theme.colorScheme.primary)
                                      : Colors.grey,
                                ),
                                tooltip: _isDeepSearchMode
                                    ? 'Выключить глубокий поиск'
                                    : 'Искать фразу внутри статьи',
                                onPressed: () {
                                  setState(() {
                                    _isDeepSearchMode = !_isDeepSearchMode;
                                    _performSearch(_currentQuery);
                                  });
                                },
                              ),
                            IconButton(
                              icon: Icon(
                                Icons.g_translate,
                                color: _isTranslated
                                    ? (isDark
                                          ? Colors.cyanAccent
                                          : theme.colorScheme.primary)
                                    : Colors.grey,
                              ),
                              tooltip: _isTranslated
                                  ? 'Показать оригинал'
                                  : 'Перевести на русский',
                              onPressed: _toggleTranslation,
                            ),
                          ],
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _hasSearched = false;
                                  _isTranslated = false;
                                  _translatedQueryText = "";
                                  _isDeepSearchMode = false;
                                  _englishBlocks.clear();
                                  _translationBlocks.clear();
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: _performSearch,
                  ),
                ),
                Expanded(
                  child: !_hasSearched
                      ? _buildWelcomeScreen(theme)
                      : Column(
                          children: [
                            if (_isTranslated)
                              _buildTranslationCard(theme, isDark),

                            Expanded(
                              child: blocksToRender.isEmpty
                                  ? Center(
                                      child: SingleChildScrollView(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _isTranslated
                                                  ? Icons.menu_book_rounded
                                                  : Icons.search_off,
                                              size: 64,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.2),
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              _isTranslated
                                                  ? 'В оффлайн-словарях перевода нет'
                                                  : 'Фраза «$_currentQuery» не найдена',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      itemCount: blocksToRender.length,
                                      itemBuilder: (ctx, i) =>
                                          _buildBlockWidget(
                                            blocksToRender[i],
                                            theme,
                                            isDark,
                                          ),
                                    ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildTranslationCard(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E1E1E)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _translationSource.contains("Онлайн")
                    ? Icons.cloud_done
                    : Icons.offline_bolt,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                _translationSource,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _translatedQueryText,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.cyanAccent : theme.colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeScreen(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_books_rounded,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'Готово к поиску!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Подключено баз: $_loadedCount', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
