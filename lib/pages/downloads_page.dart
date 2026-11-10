import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/engine/engine.dart';

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
  });

  factory DownloadItem.fromMap(Map<Object?, Object?> m) => DownloadItem(
    key: m['key'] as String? ?? '',
    name: m['name'] as String? ?? 'File',
    mime: m['mime'] as String? ?? '',
    time: DateTime.fromMillisecondsSinceEpoch(
      (m['time'] as num?)?.toInt() ?? 0,
    ),
    status: m['status'] as String? ?? 'done',
    bytes: (m['bytes'] as num?)?.toInt() ?? 0,
    total: (m['total'] as num?)?.toInt() ?? -1,
  );

  final String key;
  final String name;
  final String mime;
  final DateTime time;

  /// running, paused, done or failed.
  final String status;
  final int bytes;
  final int total;

  bool get running => status == 'running' || status == 'paused';
}

/// Human file size: 1.2 MB, 340 KB, 12 bytes.
String fileSize(int bytes) {
  if (bytes < 1000) return '$bytes bytes';
  if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(0)} KB';
  if (bytes < 1000 * 1000 * 1000) {
    return '${(bytes / 1000 / 1000).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1000 / 1000 / 1000).toStringAsFixed(1)} GB';
}

/// Files downloaded in ZT Browser: open, share or delete them.
class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});

  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  late final BrowserEngine _engine = ref.read(browserEngineProvider);
  List<DownloadItem>? _items;
  Timer? _poll;

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

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _open(DownloadItem d) async {
    if (d.status != 'done') return;
    if (!await _engine.openDownload(d.key)) {
      _snack('No app on this phone opens this kind of file');
    }
  }

  Future<void> _delete(DownloadItem d) async {
    final bool ok =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: Text(d.running ? 'Cancel download?' : 'Delete file?'),
            content: Text(
              d.running
                  ? '${d.name} stops downloading.'
                  : '${d.name} is deleted from this phone.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(d.running ? 'Cancel download' : 'Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await _engine.deleteDownload(d.key);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final List<DownloadItem>? items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Files you download show here. They are saved in your '
                  "phone's Downloads folder.",
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: <Widget>[
                  for (final DownloadItem d in items) _tile(d),
                ],
              ),
            ),
    );
  }

  Widget _tile(DownloadItem d) {
    final String detail = switch (d.status) {
      'running' when d.total > 0 =>
        '${fileSize(d.bytes)} of ${fileSize(d.total)}',
      'running' => 'Downloading…',
      'paused' => 'Waiting for a connection',
      'failed' => "Couldn't download",
      _ => fileSize(d.bytes),
    };
    return ListTile(
      leading: Icon(_icon(d)),
      title: Text(d.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: d.running && d.total > 0
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
      trailing: PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (String v) async {
          switch (v) {
            case 'open':
              await _open(d);
            case 'share':
              if (!await _engine.shareDownload(d.key)) {
                _snack("This file can't be shared");
              }
            case 'delete':
              await _delete(d);
          }
        },
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          if (d.status == 'done')
            const PopupMenuItem<String>(value: 'open', child: Text('Open')),
          if (d.status == 'done')
            const PopupMenuItem<String>(value: 'share', child: Text('Share')),
          PopupMenuItem<String>(
            value: 'delete',
            child: Text(d.running ? 'Cancel download' : 'Delete'),
          ),
        ],
      ),
    );
  }

  IconData _icon(DownloadItem d) {
    if (d.status == 'failed') return Icons.error_outline;
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
