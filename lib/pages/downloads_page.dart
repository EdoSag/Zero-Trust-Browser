import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/private_lock.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';

/// One file in the Downloads list.
class DownloadItem {
  const DownloadItem({
    required this.key,
    required this.name,
    required this.mime,
    required this.time,
    required this.status,
    required this.bytes,
    required this.total,
    this.private = false,
    this.canPause = false,
    this.canResume = false,
    this.error,
  });

  factory DownloadItem.fromMap(Map<Object?, Object?> m) => DownloadItem(
    key: m['key'] as String? ?? '',
    name: m['name'] as String? ?? '',
    mime: m['mime'] as String? ?? '',
    time: DateTime.fromMillisecondsSinceEpoch(
      (m['time'] as num?)?.toInt() ?? 0,
    ),
    status: m['status'] as String? ?? 'done',
    bytes: (m['bytes'] as num?)?.toInt() ?? 0,
    total: (m['total'] as num?)?.toInt() ?? -1,
    private: m['private'] as bool? ?? false,
    canPause: m['canPause'] as bool? ?? false,
    canResume: m['canResume'] as bool? ?? false,
    error: m['error'] as String?,
  );

  final String key;
  final String name;
  final String mime;
  final DateTime time;

  /// queued, running, waiting (for the network), paused, done or failed.
  final String status;
  final int bytes;
  final int total;

  /// From a private tab, kept encrypted in the app (B33).
  final bool private;
  final bool canPause;

  /// Paused, or failed and can be tried again from where it stopped.
  final bool canResume;

  /// Why it failed: network, http, space or gone.
  final String? error;

  /// Still going (or about to), so the list keeps updating.
  bool get running =>
      status == 'queued' || status == 'running' || status == 'waiting';

  /// Not finished: deleting it cancels it.
  bool get unfinished => status != 'done' && status != 'failed';
}

/// Files downloaded in ZT Browser: pause, resume, open, share or delete
/// them. Private downloads (B33) come first, under their own heading.
class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});

  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  late final BrowserEngine _engine = ref.read(browserEngineProvider);
  List<DownloadItem>? _items;
  Timer? _poll;
  AppL10n get l => context.l10n;

  String _name(DownloadItem d) => d.name.isEmpty ? l.fileFallbackName : d.name;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final List<DownloadItem> items = <DownloadItem>[
      for (final Map<Object?, Object?> m in await _engine.downloads())
        DownloadItem.fromMap(m),
    ];
    if (!mounted) return;
    setState(() => _items = items);
    _poll?.cancel();
    // Progress of running downloads.
    if (items.any((DownloadItem d) => d.running)) {
      _poll = Timer(const Duration(seconds: 1), _refresh);
    }
  }

  void _snack(String text, {SnackBarAction? action}) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(text),
            action: action,
            // A snackbar with an action stays until dismissed otherwise.
            duration: const Duration(seconds: 6),
          ),
        );

  /// Tells what went wrong; nothing ever fails silently.
  Future<void> _report(DownloadResult r, String failedText) async {
    if (!mounted) return;
    switch (r) {
      case DownloadResult.done:
        return;
      case DownloadResult.noApp:
        _snack(
          l.noAppOpens,
          action: SnackBarAction(
            label: l.showInFiles,
            onPressed: () => unawaited(_engine.showDownloadsFolder()),
          ),
        );
      case DownloadResult.missing:
        _snack(l.fileGone);
        await _refresh();
      case DownloadResult.failed:
        _snack(failedText);
    }
  }

  Future<void> _open(DownloadItem d) async {
    if (d.status != 'done') return;
    final String failed = l.cantOpenFile;
    await _report(await _engine.openDownload(d.key), failed);
  }

  Future<void> _share(DownloadItem d) async {
    final String failed = l.cantShare;
    await _report(await _engine.shareDownload(d.key), failed);
  }

  Future<void> _delete(DownloadItem d) async {
    final bool ok =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: Text(
              d.unfinished ? l.cancelDownloadTitle : l.deleteFileTitle,
            ),
            content: Text(
              d.unfinished
                  ? l.stopsDownloading(_name(d))
                  : l.deletedFromPhone(_name(d)),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(l.keep),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(d.unfinished ? l.cancelDownload : l.delete),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await _engine.deleteDownload(d.key);
    await _refresh();
  }

  Future<void> _pause(DownloadItem d) async {
    await _engine.pauseDownload(d.key);
    await _refresh();
  }

  Future<void> _resume(DownloadItem d) async {
    await _engine.resumeDownload(d.key);
    await _refresh();
  }

  /// A private download into the phone's Downloads, where it stays.
  Future<void> _saveToPhone(DownloadItem d) async {
    final String name = _name(d);
    final String failed = l.couldntSave(name);
    final String saved = l.savedToDownloads(name);
    final bool ok = await _engine.saveDownloadToPhone(d.key);
    if (!mounted) return;
    _snack(ok ? saved : failed);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final List<DownloadItem>? items = _items;
    final bool locked = ref.watch(privateLockProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.downloads)),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l.downloadsEmpty, textAlign: TextAlign.center),
              ),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: <Widget>[
                  if (items.any((DownloadItem d) => d.private)) ...<Widget>[
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: Text(l.privateDownloads),
                      subtitle: Text(
                        locked
                            ? l.privateDownloadsLocked
                            : l.privateDownloadsSub,
                      ),
                      // Locked private tabs (B29) lock their files too.
                      trailing: locked
                          ? TextButton.icon(
                              key: const ValueKey<String>(
                                'unlock-private-downloads',
                              ),
                              onPressed: () => ref
                                  .read(privateLockProvider.notifier)
                                  .unlock(l.privateUnlockReason),
                              icon: const Icon(Icons.lock_open),
                              label: Text(l.unlock),
                            )
                          : null,
                    ),
                    if (!locked)
                      for (final DownloadItem d in items)
                        if (d.private) _tile(d),
                    const Divider(),
                  ],
                  for (final DownloadItem d in items)
                    if (!d.private) _tile(d),
                ],
              ),
            ),
    );
  }

  String _detail(DownloadItem d) {
    final String progress = d.total > 0
        ? l.progressOf(l.fileSize(d.bytes), l.fileSize(d.total))
        : l.fileSize(d.bytes);
    return switch (d.status) {
      'queued' => l.waitingToStart,
      'running' when d.total > 0 => progress,
      'running' => l.downloadingEllipsis,
      'waiting' => l.waitingConnection,
      'paused' => l.pausedAt(progress),
      'failed' => switch (d.error) {
        'space' => l.downloadFailedSpace,
        'http' => l.downloadFailedRefused,
        'gone' => l.downloadFailedGone,
        _ => l.couldntDownload,
      },
      _ => l.fileSize(d.bytes),
    };
  }

  Widget _tile(DownloadItem d) {
    final String detail = _detail(d);
    final bool showBar = (d.running || d.status == 'paused') && d.total > 0;
    return ListTile(
      leading: Icon(_icon(d)),
      title: Text(_name(d), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: showBar
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(detail),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: d.bytes / d.total),
              ],
            )
          : Text(detail),
      onTap: () => _open(d),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (d.canPause)
            IconButton(
              tooltip: l.pauseDownload,
              icon: const Icon(Icons.pause),
              onPressed: () => _pause(d),
            )
          else if (d.canResume)
            IconButton(
              tooltip: d.status == 'failed' ? l.tryAgain : l.resumeDownload,
              icon: Icon(
                d.status == 'failed' ? Icons.refresh : Icons.play_arrow,
              ),
              onPressed: () => _resume(d),
            ),
          PopupMenuButton<String>(
            tooltip: l.more,
            onSelected: (String v) async {
              switch (v) {
                case 'open':
                  await _open(d);
                case 'share':
                  await _share(d);
                case 'phone':
                  await _saveToPhone(d);
                case 'delete':
                  await _delete(d);
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              if (d.status == 'done')
                PopupMenuItem<String>(value: 'open', child: Text(l.open)),
              if (d.status == 'done')
                PopupMenuItem<String>(value: 'share', child: Text(l.share)),
              if (d.status == 'done' && d.private)
                PopupMenuItem<String>(
                  value: 'phone',
                  child: Text(l.saveToPhone),
                ),
              PopupMenuItem<String>(
                value: 'delete',
                child: Text(d.unfinished ? l.cancelDownload : l.delete),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _icon(DownloadItem d) {
    if (d.status == 'failed') return Icons.error_outline;
    if (d.status == 'paused') return Icons.pause_circle_outline;
    if (d.running) return Icons.downloading;
    final String m = d.mime;
    if (m.startsWith('image/')) return Icons.image_outlined;
    if (m.startsWith('video/')) return Icons.movie_outlined;
    if (m.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (m == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (m.contains('zip') || m.contains('compressed')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }
}
