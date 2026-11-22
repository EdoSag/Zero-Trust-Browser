import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/downloads_page.dart';
import 'package:zerotrust_browser/pages/send_file_sheet.dart';

/// One file in the download vault.
class VaultItem {
  const VaultItem({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    required this.time,
  });

  factory VaultItem.fromMap(Map<Object?, Object?> m) => VaultItem(
    id: m['id'] as String? ?? '',
    name: m['name'] as String? ?? '',
    mime: m['mime'] as String? ?? '',
    size: (m['size'] as num?)?.toInt() ?? 0,
    time: DateTime.fromMillisecondsSinceEpoch(
      (m['time'] as num?)?.toInt() ?? 0,
    ),
  );

  final String id;
  final String name;
  final String mime;
  final int size;
  final DateTime time;

  DownloadKind get kind => downloadKind(mime, name);
}

/// How the vault asks for the phone's lock: (available, unlock). Tests
/// replace it.
class VaultUnlock {
  const VaultUnlock();

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Whether this phone has a screen lock or biometrics to ask for.
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  Future<bool> unlock(WidgetRef ref, String reason) async {
    bool ok = false;
    try {
      // The prompt is system UI: auto-lock of the whole app waits for it.
      await ref.read(vaultControllerProvider.notifier).whileShowingSystemUi(
        () async {
          ok = await _auth.authenticate(
            localizedReason: reason,
            persistAcrossBackgrounding: true,
          );
        },
      );
    } on Object {
      return false;
    }
    return ok;
  }
}

final vaultUnlockProvider = Provider<VaultUnlock>((ref) => const VaultUnlock());

/// B39: the download vault. Files kept encrypted inside ZT Browser, on this
/// phone only: the Files app and other apps can't see them. The phone's
/// lock is asked for each time the vault is opened, and again after
/// leaving the app.
class VaultPage extends ConsumerStatefulWidget {
  const VaultPage({super.key});

  @override
  ConsumerState<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends ConsumerState<VaultPage> {
  late final BrowserEngine _engine = ref.read(browserEngineProvider);
  late final AppLifecycleListener _life;
  AppL10n get l => context.l10n;

  bool _unlocked = false;
  bool _asking = false;
  bool _hasLock = true;

  /// Set while another app opens or shares a file from here (or the
  /// picker is up): coming back from it doesn't lock the vault.
  bool _handedOff = false;
  List<VaultItem>? _items;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    _life.dispose();
    unawaited(_engine.vaultClose());
    super.dispose();
  }

  void _onHide() {
    if (_asking || _handedOff || !_unlocked) return;
    setState(() {
      _unlocked = false;
      _items = null;
    });
    unawaited(_engine.vaultClose());
  }

  void _onShow() => _handedOff = false;

  Future<void> _unlock() async {
    if (_asking) return;
    final VaultUnlock lock = ref.read(vaultUnlockProvider);
    final String reason = l.vaultUnlockReason;
    _asking = true;
    try {
      final bool has = await lock.available();
      final bool ok = !has || await lock.unlock(ref, reason);
      if (!mounted) return;
      setState(() {
        _hasLock = has;
        _unlocked = ok;
      });
      if (ok) await _refresh();
    } finally {
      _asking = false;
    }
  }

  Future<void> _refresh() async {
    final List<VaultItem> items = <VaultItem>[
      for (final Map<Object?, Object?> m in await _engine.vaultList())
        VaultItem.fromMap(m),
    ];
    if (mounted) setState(() => _items = items);
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _report(DownloadResult r, String failedText) async {
    // Nothing else opened: leaving the app later locks the vault again.
    if (r != DownloadResult.done) _handedOff = false;
    if (!mounted) return;
    switch (r) {
      case DownloadResult.done:
        return;
      case DownloadResult.noApp:
        _snack(l.noAppOpens);
      case DownloadResult.missing:
        _snack(l.fileGone);
        await _refresh();
      case DownloadResult.failed:
        _snack(failedText);
    }
  }

  Future<void> _open(VaultItem v) async {
    final String failed = l.cantOpenFile;
    _handedOff = true;
    await _report(await _engine.vaultOpen(v.id), failed);
  }

  Future<void> _share(VaultItem v) async {
    final String failed = l.cantShare;
    _handedOff = true;
    await _report(await _engine.vaultShare(v.id), failed);
  }

  /// B40: to ZT Notes or another of my devices.
  Future<void> _send(VaultItem v) => showSendFileSheet(
    context,
    ref,
    name: v.name,
    mime: v.mime,
    size: v.size,
    readBytes: (int max) => _engine.vaultBytes(v.id, max),
    toNotes: () async {
      // ZT Notes comes up in front: that doesn't lock the vault.
      _handedOff = true;
      final SendResult r = await _engine.vaultSendTo(
        v.id,
        BrowserEngine.notesPackage,
      );
      if (r != SendResult.sent) _handedOff = false;
      return r;
    },
  );

  Future<void> _moveToPhone(VaultItem v) async {
    final String done = l.movedToPhone(v.name);
    final String failed = l.couldntSave(v.name);
    final bool ok = await _engine.vaultMoveToPhone(v.id);
    if (!mounted) return;
    _snack(ok ? done : failed);
    await _refresh();
  }

  Future<void> _rename(VaultItem v) async {
    final String? next = await showDialog<String>(
      context: context,
      builder: (BuildContext c) => RenameFileDialog(name: v.name),
    );
    if (next == null || next.trim().isEmpty || next == v.name) return;
    final String failed = l.couldntRename;
    final bool ok = await _engine.vaultRename(v.id, next.trim());
    if (!mounted) return;
    if (!ok) _snack(failed);
    await _refresh();
  }

  Future<void> _delete(VaultItem v) async {
    final bool ok =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: Text(l.deleteFileTitle),
            content: Text(l.deletedFromVault(v.name)),
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
    await _engine.vaultDelete(v.id);
    await _refresh();
  }

  Future<void> _addFromPhone() async {
    final bool? move = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => SimpleDialog(
        title: Text(l.addToVault),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, true),
            child: ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(l.vaultMoveFiles),
              subtitle: Text(l.vaultMoveFilesSub),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, false),
            child: ListTile(
              leading: const Icon(Icons.file_copy_outlined),
              title: Text(l.vaultCopyFiles),
              subtitle: Text(l.vaultCopyFilesSub),
            ),
          ),
        ],
      ),
    );
    if (move == null) return;
    _handedOff = true;
    final ({int added, int kept}) r = await _engine.vaultImport(move: move);
    _handedOff = false;
    if (!mounted) return;
    if (r.added > 0) {
      _snack(
        r.kept > 0 ? l.vaultAddedKept(r.added, r.kept) : l.vaultAdded(r.added),
      );
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final List<VaultItem>? items = _items;
    final int used = (items ?? const <VaultItem>[]).fold(
      0,
      (int a, VaultItem v) => a + v.size,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.downloadVault)),
      floatingActionButton: _unlocked
          ? FloatingActionButton.extended(
              onPressed: _addFromPhone,
              icon: const Icon(Icons.add),
              label: Text(l.addFromPhone),
            )
          : null,
      body: !_unlocked
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.lock_outline, size: 48),
                    const SizedBox(height: 16),
                    Text(l.vaultLocked, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      key: const ValueKey<String>('unlock-vault'),
                      onPressed: _unlock,
                      icon: const Icon(Icons.lock_open),
                      label: Text(l.unlock),
                    ),
                  ],
                ),
              ),
            )
          : items == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.enhanced_encryption_outlined),
                  title: Text(l.vaultExplain),
                  subtitle: Text(
                    l.downloadsUsed(items.length, l.fileSize(used)),
                  ),
                ),
                if (!_hasLock)
                  ListTile(
                    leading: const Icon(Icons.warning_amber_outlined),
                    title: Text(l.vaultNoScreenLock),
                  ),
                const Divider(),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(l.vaultEmpty, textAlign: TextAlign.center),
                  ),
                for (final VaultItem v in items) _tile(v),
              ],
            ),
    );
  }

  Widget _tile(VaultItem v) => ListTile(
    leading: Icon(downloadKindIcon(v.kind, v.mime)),
    title: Text(v.name, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '${l.fileSize(v.size)} · '
      '${MaterialLocalizations.of(context).formatMediumDate(v.time)}',
    ),
    onTap: () => _open(v),
    trailing: PopupMenuButton<String>(
      tooltip: l.more,
      onSelected: (String a) async {
        switch (a) {
          case 'share':
            await _share(v);
          case 'send':
            await _send(v);
          case 'phone':
            await _moveToPhone(v);
          case 'rename':
            await _rename(v);
          case 'delete':
            await _delete(v);
        }
      },
      itemBuilder: (_) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'share', child: Text(l.share)),
        PopupMenuItem<String>(value: 'send', child: Text(l.sendFileTo)),
        PopupMenuItem<String>(value: 'phone', child: Text(l.moveToPhone)),
        PopupMenuItem<String>(value: 'rename', child: Text(l.renameFile)),
        PopupMenuItem<String>(value: 'delete', child: Text(l.delete)),
      ],
    ),
  );
}
