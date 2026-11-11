import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/browser/translation.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(0);

/// "Translate page" (B16): pick the languages, download their models the
/// first time (from ZT Browser's GitHub release), then the page is
/// translated on the phone. Page text never leaves it.
Future<void> showTranslateSheet(
  BuildContext context,
  WidgetRef ref,
  BrowserTab tab,
) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppL10n l = context.l10n;
  final String appLanguage = Localizations.localeOf(context).languageCode;
  final ({String lang, String sample})? page = await ref
      .read(browserEngineProvider)
      .pageLanguage(tab.id);
  if (!context.mounted) return;
  if (page == null) {
    messenger.showSnackBar(SnackBar(content: Text(l.translateNeedsJs)));
    return;
  }
  final String? detected = detectLanguage(page.lang, page.sample);
  final bool? ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheet) => _TranslateSheet(
      tab: tab,
      detected: detected,
      appLanguage: appLanguage == 'he' ? 'he' : 'en',
    ),
  );
  if (ok == false) {
    messenger.showSnackBar(SnackBar(content: Text(l.translateNeedsJs)));
  }
}

class _TranslateSheet extends ConsumerStatefulWidget {
  const _TranslateSheet({
    required this.tab,
    required this.detected,
    required this.appLanguage,
  });

  final BrowserTab tab;
  final String? detected;
  final String appLanguage;

  @override
  ConsumerState<_TranslateSheet> createState() => _TranslateSheetState();
}

class _TranslateSheetState extends ConsumerState<_TranslateSheet> {
  ModelManifest? _manifest;
  Set<String> _installed = <String>{};
  bool _failed = false;
  String? _from;
  late String _to = widget.appLanguage;
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final TranslationModels models = ref.read(translationModelsProvider);
    setState(() => _failed = false);
    try {
      final List<TranslationModel> have = await models.installed();
      ModelManifest m;
      try {
        m = await models.manifest();
      } on Object {
        // Offline: the languages already on the phone still work.
        if (have.isEmpty) rethrow;
        m = ModelManifest(<String, TranslationModel>{
          for (final TranslationModel x in have) x.pair: x,
        });
      }
      if (!mounted) return;
      setState(() {
        _manifest = m;
        _installed = <String>{for (final TranslationModel x in have) x.pair};
        final String? d = widget.detected;
        _from = d != null && m.languages.contains(d) ? d : null;
        if (_from == _to) _to = _to == 'en' ? 'he' : 'en';
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _go(List<TranslationModel> route) async {
    final AppL10n l = context.l10n;
    final TranslationModels models = ref.read(translationModelsProvider);
    final NavigatorState nav = Navigator.of(context);
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await models.download(
        route,
        progress: (int done, int total) {
          if (mounted) {
            setState(() => _progress = total == 0 ? null : done / total);
          }
        },
      );
      // Closed while downloading: nothing to translate or close any more
      // (the navigator may be showing another screen by now).
      if (!mounted) return;
      final bool started = await models.translate(widget.tab.id, _from!, _to);
      if (mounted) nav.pop(started);
    } on Object {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = l.translateDownloadFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ModelManifest? m = _manifest;
    final List<Widget> body;
    if (_failed) {
      body = <Widget>[
        Text(l.translateListFailed),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(onPressed: _load, child: Text(l.tryAgain)),
        ),
      ];
    } else if (m == null) {
      body = const <Widget>[
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else {
      final List<String> languages = m.languages.toList()
        ..sort(
          (String a, String b) => languageName(a).compareTo(languageName(b)),
        );
      final List<TranslationModel>? route = _from == null
          ? null
          : m.route(_from!, _to);
      final List<TranslationModel> missing = <TranslationModel>[
        for (final TranslationModel x in route ?? const <TranslationModel>[])
          if (!_installed.contains(x.pair)) x,
      ];
      final int size = missing.fold(
        0,
        (int s, TranslationModel x) => s + x.downloadSize,
      );
      Widget picker(String label, String? value, ValueChanged<String> on) =>
          DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: <DropdownMenuItem<String>>[
              for (final String c in languages)
                DropdownMenuItem<String>(
                  value: c,
                  child: Text(languageName(c), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _progress != null
                ? null
                : (String? v) {
                    if (v != null) setState(() => on(v));
                  },
          );
      body = <Widget>[
        picker(l.translateFrom, _from, (String v) => _from = v),
        if (_from == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l.translatePickLanguage,
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 12),
        picker(l.translateTo, _to, (String v) => _to = v),
        const SizedBox(height: 16),
        if (_from != null && _from == _to)
          Text(l.translateSameLanguage)
        else if (_from != null && route == null)
          Text(l.translateNoModel)
        else if (missing.isNotEmpty)
          Text(
            l.translateDownloadExplain(_mb(size)),
            style: theme.textTheme.bodySmall,
          )
        else if (route != null)
          Text(l.translateOnDevice, style: theme.textTheme.bodySmall),
        if (_progress != null) ...<Widget>[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _progress),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            icon: Icon(missing.isEmpty ? Icons.translate : Icons.download),
            label: Text(
              missing.isEmpty
                  ? l.translate
                  : l.translateDownloadAndTranslate(_mb(size)),
            ),
            onPressed: route == null || _progress != null
                ? null
                : () => _go(route),
          ),
        ),
      ];
    }
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l.translatePage, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            ...body,
          ],
        ),
      ),
    );
  }
}

/// Above the toolbar while a page is shown translated: from which
/// language, progress, and "Show original".
class TranslateBar extends ConsumerWidget {
  const TranslateBar({super.key, required this.tab});

  final BrowserTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double? value = tab.translateTotal == 0
        ? null
        : tab.translateDone / tab.translateTotal;
    return Material(
      color: scheme.tertiaryContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (tab.translating)
            LinearProgressIndicator(value: value, minHeight: 2),
          SizedBox(
            height: 48,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 12),
                Icon(Icons.translate, color: scheme.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tab.translating
                        ? l.translatingFrom(
                            languageName(tab.translatedFrom ?? ''),
                          )
                        : l.translatedFrom(
                            languageName(tab.translatedFrom ?? ''),
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onTertiaryContainer),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(browserEngineProvider).showOriginal(tab.id),
                  child: Text(l.showOriginal),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _installedModelsProvider =
    FutureProvider.autoDispose<List<TranslationModel>>(
      (ref) => ref.read(translationModelsProvider).installed(),
    );

/// Settings > Translation languages: what's downloaded, and delete it.
class TranslationLanguagesPage extends ConsumerWidget {
  const TranslationLanguagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final List<TranslationModel> models =
        ref.watch(_installedModelsProvider).value ?? const <TranslationModel>[];
    return Scaffold(
      appBar: AppBar(title: Text(l.translationLanguages)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l.translationExplain),
          ),
          if (models.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l.translationNoneYet,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (final TranslationModel m in models)
            ListTile(
              leading: const Icon(Icons.translate),
              title: Text('${languageName(m.from)} → ${languageName(m.to)}'),
              subtitle: Text(l.translationModelSize(_mb(m.diskSize))),
              trailing: IconButton(
                tooltip: l.delete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await ref.read(translationModelsProvider).delete(m.pair);
                  ref.invalidate(_installedModelsProvider);
                },
              ),
            ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l.translationCredit,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
