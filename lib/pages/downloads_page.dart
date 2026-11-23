import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/private_lock.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/send_file_sheet.dart';
import 'package:zerotrust_browser/pages/vault_page.dart';

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
    this.url,
    this.canRename = false,
    this.legacy = false,
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
    url: m['url'] as String?,
    canRename: m['canRename'] as bool? ?? false,
    legacy: m['legacy'] as bool? ?? false,
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

  /// Why it failed: network, http, space or gone; "wifi" while waiting
  /// for Wi-Fi (B38).
  final String? error;

  /// The web address it came from (B36: copy link); null for a file the
  /// page made.
  final String? url;

  /// Finished, so it can get a new name (B36).
  final bool canRename;

  /// From before the download engine: listed, opened and deleted only.
  final bool legacy;

  DownloadKind get kind => downloadKind(mime, name);

  /// Still going (or about to), so the list keeps updating.
  bool get running =>
      status == 'queued' || status == 'running' || status == 'waiting';

  /// Not finished: deleting it cancels it.
  bool get unfinished => status != 'done' && status != 'failed';
}

/// B36: the filters on the Downloads page.
enum DownloadKind { images, video, audio, documents, archives, apps, other }

const Set<String> _documentExt = <String>{
  'pdf', 'doc', 'docx', 'odt', 'rtf', 'txt', 'md', 'xls', 'xlsx', 'ods', //
  'csv', 'ppt', 'pptx', 'odp', 'epub', 'html', 'htm', 'json', 'xml',
};
const Set<String> _archiveExt = <String>{
  'zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz', 'zst', //
};
const Set<String> _appExt = <String>{
  'apk',
  'apks',
  'xapk',
  'apkm',
  'exe',
  'msi',
  'dmg',
  'deb',
  'rpm',
  'appimage',
};

/// What kind of file this is, from its type and, when the site didn't say,
/// its name.
DownloadKind downloadKind(String mime, String name) {
  final String m = mime.toLowerCase();
  final int dot = name.lastIndexOf('.');
  final String ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  if (m.startsWith('image/')) return DownloadKind.images;
  if (m.startsWith('video/')) return DownloadKind.video;
  if (m.startsWith('audio/')) return DownloadKind.audio;
  if (m == 'application/vnd.android.package-archive' || _appExt.contains(ext)) {
    return DownloadKind.apps;
  }
  if (m.contains('zip') ||
      m.contains('compressed') ||
      m.contains('x-tar') ||
      _archiveExt.contains(ext)) {
    return DownloadKind.archives;
  }
  if (m == 'application/pdf' ||
      m.startsWith('text/') ||
      m.contains('document') ||
      m.contains('msword') ||
      m.contains('spreadsheet') ||
      m.contains('presentation') ||
      _documentExt.contains(ext)) {
    return DownloadKind.documents;
  }
  const Map<String, DownloadKind> byExt = <String, DownloadKind>{
    'jpg': DownloadKind.images, 'jpeg': DownloadKind.images, //
    'png': DownloadKind.images, 'gif': DownloadKind.images,
    'webp': DownloadKind.images, 'heic': DownloadKind.images,
    'mp4': DownloadKind.video, 'mkv': DownloadKind.video,
    'webm': DownloadKind.video, 'mov': DownloadKind.video,
    'mp3': DownloadKind.audio, 'm4a': DownloadKind.audio,
    'ogg': DownloadKind.audio, 'flac': DownloadKind.audio,
    'wav': DownloadKind.audio, 'opus': DownloadKind.audio,
  };
  return byExt[ext] ?? DownloadKind.other;
}

/// The items [query] (part of the name, any case) and [kind] keep.
List<DownloadItem> filterDownloads(
  List<DownloadItem> items, {
  String query = '',
  DownloadKind? kind,
}) {
  final String q = query.trim().toLowerCase();
  return <DownloadItem>[
    for (final DownloadItem d in items)
      if ((q.isEmpty || d.name.toLowerCase().contains(q)) &&
          (kind == null || d.kind == kind))
        d,
  ];
}

/// The icon for a finished file of [kind].
IconData downloadKindIcon(DownloadKind kind, String mime) => switch (kind) {
  DownloadKind.images => Icons.image_outlined,
  DownloadKind.video => Icons.movie_outlined,
  DownloadKind.audio => Icons.audiotrack_outlined,
  DownloadKind.documents =>
    mime == 'application/pdf'
        ? Icons.picture_as_pdf_outlined
        : Icons.description_outlined,
  DownloadKind.archives => Icons.folder_zip_outlined,
  DownloadKind.apps => Icons.android_outlined,
  DownloadKind.other => Icons.insert_drive_file_outlined,
};

/// The day an item is listed under: midnight of its local date.
DateTime downloadDay(DateTime t) => DateTime(t.year, t.month, t.day);

/// Files downloaded in ZT Browser: pause, resume, open, share or delete
/// them. Private downloads (B33) come first, under their own heading. B36:
/// search, filters by kind, grouped by day, select several, rename, copy
/// link, and take files off the list while keeping them.
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

  // B36: search, filter and selection.
  final TextEditingController _query = TextEditingController();
  bool _searching = false;
  DownloadKind? _kind;
  final Set<String> _selected = <String>{};
  bool get _selecting => _selected.isNotEmpty;

  String _name(DownloadItem d) => d.name.isEmpty ? l.fileFallbackName : d.name;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final List<DownloadItem> items = <DownloadItem>[
      for (final Map<Object?, Object?> m in await _engine.downloads())
        DownloadItem.fromMap(m),
    ];
    if (!mounted) return;
    setState(() {
      _items = items;
      _selected.retainAll(items.map((DownloadItem d) => d.key));
    });
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

  Future<void> _rename(DownloadItem d) async {
    final String? next = await showDialog<String>(
      context: context,
      builder: (BuildContext c) => RenameFileDialog(name: d.name),
    );
    if (next == null || next.trim().isEmpty || next == d.name) return;
    final String failed = l.couldntRename;
    final bool ok = await _engine.renameDownload(d.key, next.trim());
    if (!mounted) return;
    if (!ok) _snack(failed);
    await _refresh();
  }

  /// B40: to ZT Notes or another of my devices.
  Future<void> _send(DownloadItem d) => showSendFileSheet(
    context,
    ref,
    name: _name(d),
    mime: d.mime,
    size: d.bytes,
    readBytes: (int max) => _engine.downloadBytes(d.key, max),
    toNotes: () => _engine.sendDownloadTo(d.key, BrowserEngine.notesPackage),
  );

  /// B40: a file another device sent: into Downloads, then gone from the
  /// account.
  Future<void> _saveSent(SentFile f) async {
    final BrowserData data = ref.read(browserDataProvider);
    final String saved = l.savedToDownloads(f.name);
    final String failed = l.couldntSave(f.name);
    bool ok = false;
    try {
      ok = await _engine.saveBytesToDownloads(
        f.name,
        f.mime,
        await data.readSentFile(f),
      );
      if (ok) await data.dismissSentFile(f);
    } on Object {
      ok = false;
    }
    if (!mounted) return;
    _snack(ok ? saved : failed);
    await _refresh();
  }

  Future<void> _dismissSent(SentFile f) async {
    try {
      await ref.read(browserDataProvider).dismissSentFile(f);
    } on Object {
      if (mounted) _snack(l.couldntSend);
    }
  }

  /// B39: into the vault, encrypted, and off the phone.
  Future<void> _moveToVault(DownloadItem d) async {
    final String done = l.movedToVault(_name(d));
    final String failed = l.couldntMoveToVault;
    final bool ok = await _engine.vaultAddDownload(d.key);
    if (!mounted) return;
    _snack(
      ok ? done : failed,
      action: ok
          ? SnackBarAction(label: l.openVault, onPressed: _openVault)
          : null,
    );
    await _refresh();
  }

  void _openVault() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const VaultPage()));

  Future<void> _copyLink(DownloadItem d) async {
    final String? url = d.url;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) _snack(l.copied);
  }

  /// Off the list; the files stay where they are (private ones have no
  /// other place, so they go).
  Future<void> _forget(Iterable<String> keys) async {
    final List<String> list = keys.toList();
    if (list.isEmpty) return;
    await _engine.forgetDownloads(list);
    setState(_selected.clear);
    await _refresh();
  }

  Future<void> _clearList() async {
    final List<DownloadItem> items = _items ?? const <DownloadItem>[];
    final bool ok =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: Text(l.clearDownloadList),
            content: Text(l.clearDownloadListSub),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(l.clear),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await _forget(<String>[
      for (final DownloadItem d in items)
        if (!d.private && !d.unfinished) d.key,
    ]);
  }

  Future<void> _deleteSelected() async {
    final List<DownloadItem> chosen = <DownloadItem>[
      for (final DownloadItem d in _items ?? const <DownloadItem>[])
        if (_selected.contains(d.key)) d,
    ];
    if (chosen.isEmpty) return;
    final bool ok =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: Text(l.deleteFilesTitle(chosen.length)),
            content: Text(l.deleteFilesSub),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(l.keep),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(l.delete),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    for (final DownloadItem d in chosen) {
      await _engine.deleteDownload(d.key);
    }
    setState(_selected.clear);
    await _refresh();
  }

  void _toggle(DownloadItem d) => setState(() {
    if (!_selected.remove(d.key)) _selected.add(d.key);
  });

  PreferredSizeWidget _appBar(List<DownloadItem> shown) {
    if (_selecting) {
      return AppBar(
        leading: IconButton(
          tooltip: l.close,
          icon: const Icon(Icons.close),
          onPressed: () => setState(_selected.clear),
        ),
        title: Text(l.selectedCount(_selected.length)),
        actions: <Widget>[
          IconButton(
            tooltip: l.selectAll,
            icon: const Icon(Icons.select_all),
            onPressed: () => setState(
              () => _selected.addAll(shown.map((DownloadItem d) => d.key)),
            ),
          ),
          IconButton(
            tooltip: l.removeFromList,
            icon: const Icon(Icons.playlist_remove),
            onPressed: () => _forget(_selected.toList()),
          ),
          IconButton(
            tooltip: l.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteSelected,
          ),
        ],
      );
    }
    return AppBar(
      title: _searching
          ? TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l.searchDownloads,
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            )
          : Text(l.downloads),
      actions: <Widget>[
        if (!_searching)
          IconButton(
            tooltip: l.downloadVault,
            icon: const Icon(Icons.enhanced_encryption_outlined),
            onPressed: _openVault,
          ),
        IconButton(
          tooltip: _searching ? l.close : l.searchDownloads,
          icon: Icon(_searching ? Icons.close : Icons.search),
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) _query.clear();
          }),
        ),
        PopupMenuButton<String>(
          tooltip: l.menu,
          onSelected: (String v) {
            if (v == 'clear') _clearList();
          },
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'clear',
              child: Text(l.clearDownloadList),
            ),
          ],
        ),
      ],
    );
  }

  String _kindLabel(DownloadKind k) => switch (k) {
    DownloadKind.images => l.kindImages,
    DownloadKind.video => l.kindVideo,
    DownloadKind.audio => l.kindAudio,
    DownloadKind.documents => l.kindDocuments,
    DownloadKind.archives => l.kindArchives,
    DownloadKind.apps => l.kindApps,
    DownloadKind.other => l.kindOther,
  };

  String _dayLabel(DateTime day) {
    final DateTime today = downloadDay(DateTime.now());
    if (day == today) return l.today;
    if (day == today.subtract(const Duration(days: 1))) return l.yesterday;
    return MaterialLocalizations.of(context).formatMediumDate(day);
  }

  @override
  Widget build(BuildContext context) {
    final List<DownloadItem>? items = _items;
    final bool locked = ref.watch(privateLockProvider);
    final List<SentFile> sent =
        ref.watch(sentFilesToMeProvider).value ?? const <SentFile>[];
    final List<DownloadItem> shown = items == null
        ? const <DownloadItem>[]
        : filterDownloads(items, query: _query.text, kind: _kind);
    final Set<DownloadKind> kinds = <DownloadKind>{
      for (final DownloadItem d in items ?? const <DownloadItem>[]) d.kind,
    };
    final List<DownloadItem> normal = <DownloadItem>[
      for (final DownloadItem d in shown)
        if (!d.private) d,
    ];
    final int used = <int>[
      for (final DownloadItem d in items ?? const <DownloadItem>[])
        if (d.status == 'done') d.bytes,
    ].fold(0, (int a, int b) => a + b);
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: _appBar(shown),
        body: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty && sent.isEmpty
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
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        8,
                        16,
                        0,
                      ),
                      child: Text(
                        l.downloadsUsed(items.length, l.fileSize(used)),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (kinds.length > 1)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: <Widget>[
                            for (final DownloadKind k in DownloadKind.values)
                              if (kinds.contains(k))
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: FilterChip(
                                    label: Text(_kindLabel(k)),
                                    selected: _kind == k,
                                    onSelected: (bool on) =>
                                        setState(() => _kind = on ? k : null),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          l.noMatchingDownloads,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (sent.isNotEmpty && !_selecting) ...<Widget>[
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          16,
                          16,
                          16,
                          4,
                        ),
                        child: Text(
                          l.sentFromDevices,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      for (final SentFile f in sent) _sentTile(f),
                      const Divider(),
                    ],
                    if (shown.any((DownloadItem d) => d.private)) ...<Widget>[
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
                        for (final DownloadItem d in shown)
                          if (d.private) _tile(d),
                      const Divider(),
                    ],
                    for (int i = 0; i < normal.length; i++) ...<Widget>[
                      if (i == 0 ||
                          downloadDay(normal[i].time) !=
                              downloadDay(normal[i - 1].time))
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            16,
                            16,
                            16,
                            4,
                          ),
                          child: Text(
                            _dayLabel(downloadDay(normal[i].time)),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      _tile(normal[i]),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _sentTile(SentFile f) => ListTile(
    key: ValueKey<String>('sent-${f.id}'),
    leading: Icon(downloadKindIcon(downloadKind(f.mime, f.name), f.mime)),
    title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(l.sentFileFrom(f.fromName, l.fileSize(f.file.size))),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextButton(onPressed: () => _saveSent(f), child: Text(l.save)),
        IconButton(
          tooltip: l.dismissSentFile,
          icon: const Icon(Icons.close),
          onPressed: () => _dismissSent(f),
        ),
      ],
    ),
  );

  String _detail(DownloadItem d) {
    final String progress = d.total > 0
        ? l.progressOf(l.fileSize(d.bytes), l.fileSize(d.total))
        : l.fileSize(d.bytes);
    return switch (d.status) {
      'queued' => l.waitingToStart,
      'running' when d.total > 0 => progress,
      'running' => l.downloadingEllipsis,
      'waiting' when d.error == 'wifi' => l.waitingWifi,
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
    final bool selected = _selected.contains(d.key);
    return ListTile(
      selected: selected,
      leading: _selecting
          ? Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked)
          : Icon(_icon(d)),
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
      onTap: () => _selecting ? _toggle(d) : _open(d),
      onLongPress: () => _toggle(d),
      trailing: _selecting
          ? null
          : Row(
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
                    tooltip: d.status == 'failed'
                        ? l.tryAgain
                        : l.resumeDownload,
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
                      case 'rename':
                        await _rename(d);
                      case 'link':
                        await _copyLink(d);
                      case 'send':
                        await _send(d);
                      case 'vault':
                        await _moveToVault(d);
                      case 'forget':
                        await _forget(<String>[d.key]);
                      case 'delete':
                        await _delete(d);
                    }
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    if (d.status == 'done')
                      PopupMenuItem<String>(value: 'open', child: Text(l.open)),
                    if (d.status == 'done')
                      PopupMenuItem<String>(
                        value: 'share',
                        child: Text(l.share),
                      ),
                    if (d.status == 'done' && d.private)
                      PopupMenuItem<String>(
                        value: 'phone',
                        child: Text(l.saveToPhone),
                      ),
                    if (d.canRename && !d.legacy)
                      PopupMenuItem<String>(
                        value: 'rename',
                        child: Text(l.renameFile),
                      ),
                    if (d.url != null)
                      PopupMenuItem<String>(
                        value: 'link',
                        child: Text(l.copyLink),
                      ),
                    if (d.status == 'done' && !d.legacy)
                      PopupMenuItem<String>(
                        value: 'send',
                        child: Text(l.sendFileTo),
                      ),
                    if (d.status == 'done' && !d.legacy)
                      PopupMenuItem<String>(
                        value: 'vault',
                        child: Text(l.moveToVault),
                      ),
                    if (!d.unfinished && !d.private)
                      PopupMenuItem<String>(
                        value: 'forget',
                        child: Text(l.removeFromList),
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
    return downloadKindIcon(d.kind, d.mime);
  }
}

/// The new name for a download; owns its text field's controller so it
/// lives as long as the dialog does (closing animates).
class RenameFileDialog extends StatefulWidget {
  const RenameFileDialog({super.key, required this.name});

  final String name;

  @override
  State<RenameFileDialog> createState() => _RenameFileDialogState();
}

class _RenameFileDialogState extends State<RenameFileDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.name)
        ..selection = TextSelection(
          baseOffset: 0,
          // The name without its extension is selected, ready to retype.
          extentOffset: widget.name.lastIndexOf('.') > 0
              ? widget.name.lastIndexOf('.')
              : widget.name.length,
        );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    return AlertDialog(
      title: Text(l.renameFile),
      content: TextField(
        controller: _name,
        autofocus: true,
        decoration: InputDecoration(labelText: l.fileName),
        onSubmitted: (String v) => Navigator.pop(context, v),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _name.text),
          child: Text(l.save),
        ),
      ],
    );
  }
}
