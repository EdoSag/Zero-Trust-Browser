import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/user_script.dart';
import 'package:zerotrust_browser/browser/user_scripts.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';

/// Where people find scripts.
const String scriptLibraryUrl = 'https://greasyfork.org/';

/// B41: the user's scripts. Add from a link, a file or by pasting; switch
/// each on or off; tap one for its sites, permissions and updates.
class ScriptsPage extends ConsumerWidget {
  const ScriptsPage({super.key, this.onOpen});

  /// Opens a web page in a new tab (Greasy Fork); null hides the link.
  final void Function(String url)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final List<UserScript> scripts =
        ref.watch(userScriptsProvider).value ?? const <UserScript>[];
    final UserScriptsService service = ref.read(userScriptsServiceProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.scripts)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addScript(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l.addScript),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(l.scriptsExplain),
          ),
          if (onOpen != null)
            ListTile(
              leading: const Icon(Icons.travel_explore),
              title: Text(l.findScripts),
              onTap: () => onOpen!(scriptLibraryUrl),
            ),
          const Divider(),
          for (final UserScript s in scripts)
            _ScriptTile(
              script: s,
              onChanged: (bool v) => service.save(s.copyWith(enabled: v)),
            ),
          if (scripts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(l.scriptsCount(0))),
            ),
        ],
      ),
    );
  }
}

class _ScriptTile extends StatelessWidget {
  const _ScriptTile({required this.script, required this.onChanged});

  final UserScript script;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final UserScriptMeta? m = script.meta;
    final String lang = Localizations.localeOf(context).languageCode;
    final List<String>? sites = m?.sites;
    return ListTile(
      leading: const Icon(Icons.code),
      title: Text(m?.nameIn(lang) ?? l.scriptUnreadable),
      subtitle: Text(
        <String>[
          if (m?.version != null) l.scriptVersion(m!.version!),
          if (m != null)
            sites == null
                ? l.scriptEverywhere
                : l.scriptSitesCount(sites.length),
        ].join(' · '),
      ),
      trailing: Switch(value: script.enabled, onChanged: onChanged),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ScriptDetailPage(scriptId: script.id),
        ),
      ),
    );
  }
}

/// Asks where the new script comes from, then shows it for review.
Future<void> _addScript(BuildContext context, WidgetRef ref) async {
  final AppL10n l = context.l10n;
  final String? how = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(l.addScriptFromLink),
            onTap: () => Navigator.pop(sheet, 'link'),
          ),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: Text(l.addScriptFromFile),
            onTap: () => Navigator.pop(sheet, 'file'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(l.addScriptPaste),
            onTap: () => Navigator.pop(sheet, 'paste'),
          ),
        ],
      ),
    ),
  );
  if (how == null || !context.mounted) return;
  switch (how) {
    case 'link':
      final String? url = await _askScriptUrl(context);
      if (url == null || !context.mounted) return;
      await reviewScriptFromUrl(context, url);
    case 'file':
      final Uint8List? bytes = await ref
          .read(browserEngineProvider)
          .pickFile(const <String>[
            'text/javascript',
            'application/javascript',
            'application/x-javascript',
            'text/plain',
            '*/*',
          ]);
      if (bytes == null || !context.mounted) return;
      final String code = utf8.decode(bytes, allowMalformed: true);
      await reviewScript(context, (UserScriptsService s) => s.prepare(code));
    case 'paste':
      final String? code = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(builder: (_) => const ScriptEditorPage()),
      );
      if (code == null || !context.mounted) return;
      await reviewScript(context, (UserScriptsService s) => s.prepare(code));
  }
}

Future<String?> _askScriptUrl(BuildContext context) async {
  final AppL10n l = context.l10n;
  final TextEditingController c = TextEditingController();
  String? error;
  final String? result = await showDialog<String>(
    context: context,
    builder: (BuildContext d) => StatefulBuilder(
      builder: (BuildContext d, StateSetter set) {
        void done() {
          final String? url = webAddress(c.text.trim());
          if (url == null) {
            set(() => error = l.scriptLinkInvalid);
            return;
          }
          Navigator.pop(d, url);
        }

        return AlertDialog(
          title: Text(l.addScriptFromLink),
          content: TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              hintText: l.scriptLinkHint,
              errorText: error,
            ),
            onSubmitted: (_) => done(),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: Text(l.cancel),
            ),
            FilledButton(onPressed: done, child: Text(l.next)),
          ],
        );
      },
    ),
  );
  c.dispose();
  return result;
}

/// Downloads the script at [url] and shows it for review (a .user.js link
/// tapped on a page lands here too).
Future<void> reviewScriptFromUrl(BuildContext context, String url) =>
    reviewScript(
      context,
      (UserScriptsService s) async =>
          s.prepare(await s.download(url), sourceUrl: url),
    );

/// Shows the install screen for the script [load] gives; nothing is
/// installed unless the user taps Install there.
Future<void> reviewScript(
  BuildContext context,
  Future<PreparedScript?> Function(UserScriptsService service) load,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => ScriptInstallPage(load: load),
  ),
);

String problemText(AppL10n l, Object e) {
  if (e is ScriptException) {
    return switch (e.problem) {
      ScriptProblem.notAScript => l.scriptNotAScript,
      ScriptProblem.download => l.scriptDownloadFailed,
      ScriptProblem.dependency => l.scriptDependencyFailed(e.detail ?? ''),
      ScriptProblem.tooLarge => l.scriptTooLarge,
    };
  }
  return l.scriptDownloadFailed;
}

/// What a script will be able to do, before it is installed or updated.
class ScriptInstallPage extends ConsumerStatefulWidget {
  const ScriptInstallPage({super.key, required this.load});

  /// The script to review; null means there is nothing new (no update).
  final Future<PreparedScript?> Function(UserScriptsService service) load;

  @override
  ConsumerState<ScriptInstallPage> createState() => _ScriptInstallPageState();
}

class _ScriptInstallPageState extends ConsumerState<ScriptInstallPage> {
  late final Future<PreparedScript?> _prepared = widget.load(
    ref.read(userScriptsServiceProvider),
  );
  bool _showCode = false;
  bool _saving = false;

  Future<void> _install(PreparedScript p) async {
    final AppL10n l = context.l10n;
    setState(() => _saving = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await ref.read(userScriptsServiceProvider).install(p);
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          p.existing == null
              ? l.scriptInstalled(p.meta.name)
              : l.scriptUpdated(p.meta.name),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    return FutureBuilder<PreparedScript?>(
      future: _prepared,
      builder: (BuildContext context, AsyncSnapshot<PreparedScript?> snap) {
        final PreparedScript? p = snap.data;
        Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(l.scriptLoading),
              ],
            ),
          );
        } else if (snap.hasError) {
          body = _Message(
            icon: Icons.error_outline,
            text: problemText(l, snap.error!),
          );
        } else if (p == null) {
          body = _Message(
            icon: Icons.check_circle_outline,
            text: l.scriptUpToDate,
          );
        } else {
          body = _review(context, p);
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(l.reviewScript),
            leading: IconButton(
              tooltip: l.cancel,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: body,
          bottomNavigationBar: p == null
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(l.cancel),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving ? null : () => _install(p),
                            child: Text(
                              p.existing == null
                                  ? l.installScript
                                  : l.updateScript,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _review(BuildContext context, PreparedScript p) {
    final AppL10n l = context.l10n;
    final ThemeData theme = Theme.of(context);
    final UserScriptMeta m = p.meta;
    final String lang = Localizations.localeOf(context).languageCode;
    final List<String>? sites = m.sites;
    final List<String>? connect = m.connectSites;
    final Set<String> newSites = p.newSites.toSet();
    final Set<String> newConnect = p.newConnectSites.toSet();
    final Set<ScriptPermission> newPerms = p.newPermissions;
    final String? oldVersion = p.existing?.meta?.version;
    final List<String> requireHosts = <String>{
      for (final String u in m.requires) Uri.tryParse(u)?.host ?? u,
    }.toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.code, size: 36),
          title: Text(m.nameIn(lang), style: theme.textTheme.titleLarge),
          subtitle: Text(
            <String>[
              if (p.existing != null && oldVersion != m.version)
                l.scriptVersionChange(oldVersion ?? '?', m.version ?? '?')
              else if (m.version != null)
                l.scriptVersion(m.version!),
              if (m.author != null) m.author!,
            ].join(' · '),
          ),
        ),
        if (m.descriptionIn(lang) != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(m.descriptionIn(lang)!),
          ),
        if (p.sourceUrl != null)
          _Labeled(label: l.scriptSource, value: p.sourceUrl!, ltr: true),
        Card(
          margin: const EdgeInsets.all(16),
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.scriptWarning,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
        _Header(l.scriptRunsOn),
        if (sites == null)
          _Item(
            icon: Icons.public,
            text: l.scriptAllSites,
            isNew: p.newlyEverywhere,
            strong: true,
          )
        else
          for (final String s in sites)
            _Item(
              icon: Icons.language,
              text: s,
              ltr: true,
              isNew: newSites.contains(s),
            ),
        if (m.usesNetwork) ...<Widget>[
          _Header(l.scriptSendsTo),
          if (connect == null)
            _Item(
              icon: Icons.public,
              text: l.scriptSendsAnywhere,
              isNew: p.newlyConnectsAnywhere,
              strong: true,
            )
          else
            for (final String s in connect)
              _Item(
                icon: Icons.upload_outlined,
                text: s,
                ltr: true,
                isNew: newConnect.contains(s),
              ),
        ],
        if (m.permissions.isNotEmpty) ...<Widget>[
          _Header(l.scriptAlsoCan),
          for (final ScriptPermission perm in ScriptPermission.values)
            if (m.permissions.contains(perm))
              _Item(
                icon: _permissionIcon(perm),
                text: permissionText(l, perm),
                isNew: newPerms.contains(perm),
              ),
        ],
        if (requireHosts.isNotEmpty) ...<Widget>[
          _Header(l.scriptFilesFrom),
          for (final String h in requireHosts)
            _Item(icon: Icons.download_outlined, text: h, ltr: true),
        ],
        if (m.unsupportedGrants.isNotEmpty) ...<Widget>[
          _Header(l.scriptUnsupported),
          for (final String g in m.unsupportedGrants)
            _Item(icon: Icons.block, text: g, ltr: true),
        ],
        if (m.runAt == 'context-menu')
          _Item(icon: Icons.block, text: l.scriptContextMenuUnsupported),
        const Divider(height: 32),
        ListTile(
          leading: Icon(_showCode ? Icons.expand_less : Icons.expand_more),
          title: Text(l.scriptShowCode),
          onTap: () => setState(() => _showCode = !_showCode),
        ),
        if (_showCode) _CodeView(code: p.code),
      ],
    );
  }
}

IconData _permissionIcon(ScriptPermission p) => switch (p) {
  ScriptPermission.storage => Icons.save_outlined,
  ScriptPermission.network => Icons.cloud_upload_outlined,
  ScriptPermission.tabs => Icons.tab_outlined,
  ScriptPermission.clipboard => Icons.content_paste,
  ScriptPermission.notifications => Icons.notifications_none,
  ScriptPermission.menu => Icons.menu,
};

String permissionText(AppL10n l, ScriptPermission p) => switch (p) {
  ScriptPermission.storage => l.permStorage,
  ScriptPermission.network => l.permNetwork,
  ScriptPermission.tabs => l.permTabs,
  ScriptPermission.clipboard => l.permClipboard,
  ScriptPermission.notifications => l.permNotifications,
  ScriptPermission.menu => l.permMenu,
};

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.text,
    this.ltr = false,
    this.isNew = false,
    this.strong = false,
  });

  final IconData icon;
  final String text;
  final bool ltr;
  final bool isNew;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(icon, color: strong ? theme.colorScheme.error : null),
      title: Text(
        text,
        textDirection: ltr ? TextDirection.ltr : null,
        textAlign: ltr && Directionality.of(context) == TextDirection.rtl
            ? TextAlign.right
            : null,
        style: strong
            ? TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
      trailing: isNew
          ? Chip(
              label: Text(context.l10n.scriptNew),
              visualDensity: VisualDensity.compact,
            )
          : null,
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.value, this.ltr = false});
  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(label),
    subtitle: Text(
      value,
      textDirection: ltr ? TextDirection.ltr : null,
      textAlign: ltr && Directionality.of(context) == TextDirection.rtl
          ? TextAlign.right
          : null,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 48),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _CodeView extends StatelessWidget {
  const _CodeView({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    // Very long scripts: the start is enough to look at here.
    final String shown = code.length > 60000
        ? '${code.substring(0, 60000)}\n…'
        : code;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          shown,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}

/// One script: on or off, private tabs, sites, permissions, updates, code.
class ScriptDetailPage extends ConsumerWidget {
  const ScriptDetailPage({super.key, required this.scriptId});

  final String scriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final List<UserScript> all =
        ref.watch(userScriptsProvider).value ?? const <UserScript>[];
    final UserScript? s = all
        .where((UserScript u) => u.id == scriptId)
        .firstOrNull;
    if (s == null) {
      return Scaffold(appBar: AppBar());
    }
    final UserScriptsService service = ref.read(userScriptsServiceProvider);
    final UserScriptMeta? m = s.meta;
    final String lang = Localizations.localeOf(context).languageCode;
    final List<String>? sites = m?.sites;
    final List<String>? connect = m?.connectSites;

    return Scaffold(
      appBar: AppBar(title: Text(m?.nameIn(lang) ?? l.scriptUnreadable)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          if (m?.descriptionIn(lang) != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(m!.descriptionIn(lang)!),
            ),
          if (m?.version != null || m?.author != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                <String>[
                  if (m?.version != null) l.scriptVersion(m!.version!),
                  if (m?.author != null) m!.author!,
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.power_settings_new),
            title: Text(l.scriptOn),
            value: s.enabled,
            onChanged: (bool v) => service.save(s.copyWith(enabled: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.privacy_tip_outlined),
            title: Text(l.scriptRunPrivate),
            subtitle: Text(l.scriptRunPrivateSub),
            value: s.allowPrivate,
            onChanged: (bool v) => service.save(s.copyWith(allowPrivate: v)),
          ),
          if (m != null) ...<Widget>[
            _Header(l.scriptRunsOn),
            if (sites == null)
              _Item(icon: Icons.public, text: l.scriptAllSites, strong: true)
            else
              for (final String site in sites)
                _Item(icon: Icons.language, text: site, ltr: true),
            if (m.usesNetwork) ...<Widget>[
              _Header(l.scriptSendsTo),
              if (connect == null)
                _Item(
                  icon: Icons.public,
                  text: l.scriptSendsAnywhere,
                  strong: true,
                )
              else
                for (final String c in connect)
                  _Item(icon: Icons.upload_outlined, text: c, ltr: true),
            ],
            if (m.permissions.isNotEmpty) ...<Widget>[
              _Header(l.scriptAlsoCan),
              for (final ScriptPermission perm in ScriptPermission.values)
                if (m.permissions.contains(perm))
                  _Item(
                    icon: _permissionIcon(perm),
                    text: permissionText(l, perm),
                  ),
            ],
            if (m.unsupportedGrants.isNotEmpty) ...<Widget>[
              _Header(l.scriptUnsupported),
              for (final String g in m.unsupportedGrants)
                _Item(icon: Icons.block, text: g, ltr: true),
            ],
          ],
          const Divider(height: 32),
          if (s.updateUrl != null)
            ListTile(
              leading: const Icon(Icons.system_update_alt),
              title: Text(l.checkForUpdate),
              subtitle: Text(l.checkForUpdateSub),
              onTap: () => reviewScript(
                context,
                (UserScriptsService svc) => svc.checkForUpdate(s),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l.editCode),
            onTap: () async {
              final String? code = await Navigator.of(context).push<String>(
                MaterialPageRoute<String>(
                  builder: (_) => ScriptEditorPage(initial: s.code),
                ),
              );
              if (code == null || code == s.code || !context.mounted) return;
              await reviewScript(
                context,
                (UserScriptsService svc) => svc.prepare(code, existing: s),
              );
            },
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              l.delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () async {
              final String name = m?.nameIn(lang) ?? l.scriptUnreadable;
              final bool yes =
                  await showDialog<bool>(
                    context: context,
                    builder: (BuildContext d) => AlertDialog(
                      title: Text(l.deleteScriptQ(name)),
                      content: Text(l.deleteScriptExplain),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(d, false),
                          child: Text(l.cancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: Text(l.delete),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (!yes || !context.mounted) return;
              Navigator.of(context).pop();
              await service.delete(s);
            },
          ),
        ],
      ),
    );
  }
}

/// Write or paste a script; returns its code.
class ScriptEditorPage extends StatefulWidget {
  const ScriptEditorPage({super.key, this.initial});

  final String? initial;

  @override
  State<ScriptEditorPage> createState() => _ScriptEditorPageState();
}

const String _template = '''// ==UserScript==
// @name        My script
// @version     1.0
// @match       https://example.com/*
// @grant       none
// ==/UserScript==

''';

class _ScriptEditorPageState extends State<ScriptEditorPage> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial ?? _template,
  );
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() {
    if (UserScriptMeta.parse(_c.text) == null) {
      setState(() => _error = context.l10n.scriptNotAScript);
      return;
    }
    Navigator.of(context).pop(_c.text);
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? l.newScript : l.editCode),
        actions: <Widget>[TextButton(onPressed: _done, child: Text(l.next))],
      ),
      body: Column(
        children: <Widget>[
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: <Widget>[
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: Text(l.close),
                ),
              ],
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _c,
                expands: true,
                maxLines: null,
                minLines: null,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.multiline,
                textDirection: TextDirection.ltr,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: l.scriptEditorHint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
