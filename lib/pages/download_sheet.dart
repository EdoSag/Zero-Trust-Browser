import 'package:flutter/material.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/download_check.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';

/// A file a page offered to download, waiting for "Save" or "Cancel"
/// (B35). From the engine's `downloadRequest` event.
class DownloadRequest {
  const DownloadRequest({
    required this.requestId,
    required this.name,
    required this.mime,
    required this.size,
    required this.url,
    this.pageUrl,
    this.private = false,
  });

  factory DownloadRequest.fromMap(Map<Object?, Object?> m) => DownloadRequest(
    requestId: (m['requestId'] as num?)?.toInt() ?? 0,
    name: m['name'] as String? ?? '',
    mime: m['mime'] as String? ?? '',
    size: (m['size'] as num?)?.toInt() ?? -1,
    url: m['url'] as String? ?? '',
    pageUrl: m['pageUrl'] as String?,
    private: m['private'] as bool? ?? false,
  );

  final int requestId;

  /// As the site named it (checked as is, shown cleaned).
  final String name;
  final String mime;

  /// Bytes, or -1 when the site didn't say.
  final int size;

  /// The file's address; for a file the page made, `blob:...` or the start
  /// of `data:...`.
  final String url;
  final String? pageUrl;
  final bool private;

  Set<DownloadWarning> get warnings =>
      downloadWarnings(name: name, mime: mime, url: url);

  /// The site it comes from: the file's own, or the page's for a file the
  /// page made.
  String get site {
    final String own = hostOf(url);
    return own.isNotEmpty ? own : hostOf(pageUrl);
  }
}

/// What the person chose in the sheet.
class DownloadChoice {
  const DownloadChoice({
    required this.name,
    required this.keepPrivate,
    required this.openWhenDone,
  });

  final String name;
  final bool keepPrivate;
  final bool openWhenDone;
}

/// "Save this file?": the name (editable), size, type and site, warnings
/// for risky files, and from a private tab where it goes. Null = cancel.
Future<DownloadChoice?> showDownloadSheet(
  BuildContext context,
  DownloadRequest request,
) => showModalBottomSheet<DownloadChoice>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  // Never under the status bar, however tall the sheet gets.
  useSafeArea: true,
  builder: (_) => DownloadSheet(request: request),
);

class DownloadSheet extends StatefulWidget {
  const DownloadSheet({required this.request, super.key});

  final DownloadRequest request;

  @override
  State<DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<DownloadSheet> {
  late final TextEditingController _name = TextEditingController(
    text: cleanFileName(widget.request.name),
  );
  late final Set<DownloadWarning> _warnings = widget.request.warnings;
  bool _keepPrivate = true;
  bool _openWhenDone = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(
    context,
    DownloadChoice(
      name: cleanFileName(
        _name.text.trim().isEmpty ? widget.request.name : _name.text,
      ),
      keepPrivate: _keepPrivate,
      openWhenDone: _openWhenDone,
    ),
  );

  String _warningText(AppL10n l, DownloadWarning w) => switch (w) {
    DownloadWarning.app => l.downloadWarnApp,
    DownloadWarning.program => l.downloadWarnProgram,
    DownloadWarning.disguised => l.downloadWarnDisguised,
    DownloadWarning.insecure => l.downloadWarnInsecure,
  };

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final ThemeData theme = Theme.of(context);
    final DownloadRequest r = widget.request;
    final bool risky = _warnings.isNotEmpty;
    final String type = r.mime.isEmpty || r.mime == 'application/octet-stream'
        ? fileExtension(_name.text).toUpperCase()
        : r.mime;
    // Cancel and Save stay pinned under the rest, above the keyboard and the
    // gesture bar; only the part over them scrolls when it doesn't fit.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      r.private ? l.saveFilePrivateTitle : l.saveFileTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey<String>('download-name'),
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: l.fileName,
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      <String>[
                        if (r.size >= 0) l.fileSize(r.size) else l.sizeUnknown,
                        if (type.isNotEmpty) type,
                        if (r.site.isNotEmpty) l.fromSite(r.site),
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    for (final DownloadWarning w in _warnings) ...<Widget>[
                      const SizedBox(height: 12),
                      _Warning(text: _warningText(l, w)),
                    ],
                    if (r.private) ...<Widget>[
                      const SizedBox(height: 8),
                      RadioGroup<bool>(
                        groupValue: _keepPrivate,
                        onChanged: (bool? v) =>
                            setState(() => _keepPrivate = v ?? true),
                        child: Column(
                          children: <Widget>[
                            RadioListTile<bool>(
                              key: const ValueKey<String>(
                                'download-keep-private',
                              ),
                              contentPadding: EdgeInsets.zero,
                              value: true,
                              title: Text(l.keepPrivate),
                              subtitle: Text(l.keepPrivateSub),
                            ),
                            RadioListTile<bool>(
                              key: const ValueKey<String>(
                                'download-save-phone',
                              ),
                              contentPadding: EdgeInsets.zero,
                              value: false,
                              title: Text(l.saveToPhone),
                              subtitle: Text(l.saveToPhoneSub),
                            ),
                          ],
                        ),
                      ),
                    ],
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _openWhenDone,
                      onChanged: (bool? v) =>
                          setState(() => _openWhenDone = v ?? false),
                      title: Text(l.openWhenDone),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 16),
              // Each button gets half the row. The shared look makes filled
              // and outlined buttons as wide as they are allowed to be, so
              // one put in a row without Expanded has no width to take and
              // is not drawn at all.
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey<String>('download-cancel'),
                      onPressed: () => Navigator.pop(context),
                      child: Text(l.cancel, textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: risky
                        ? FilledButton.tonal(
                            key: const ValueKey<String>('download-save'),
                            onPressed: _save,
                            child: Text(
                              l.saveAnyway,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : FilledButton(
                            key: const ValueKey<String>('download-save'),
                            onPressed: _save,
                            child: Text(l.save, textAlign: TextAlign.center),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: c.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: c.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}
