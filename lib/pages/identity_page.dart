import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/identity.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';

/// The phone's engine version and what the default identity sends.
final deviceIdentityProvider = FutureProvider<DeviceIdentity>(
  (ref) async => DeviceIdentity.fromMap(
    await ref.read(browserEngineProvider).identityInfo(),
  ),
);

/// In the tab sheet: follow the settings (no choice of its own).
const String _asSettings = '+settings';

String _browserName(IdentityBrowser b) => switch (b) {
  IdentityBrowser.chrome => 'Chrome',
  IdentityBrowser.edge => 'Edge',
  IdentityBrowser.opera => 'Opera',
  IdentityBrowser.samsung => 'Samsung Internet',
  IdentityBrowser.firefox => 'Firefox',
  IdentityBrowser.safari => 'Safari',
  IdentityBrowser.other => '',
};

String _systemName(IdentitySystem s) => switch (s) {
  IdentitySystem.android => 'Android',
  IdentitySystem.windows => 'Windows',
  IdentitySystem.mac => 'Mac',
  IdentitySystem.linux => 'Linux',
  IdentitySystem.chromeOs => 'ChromeOS',
  IdentitySystem.iphone => 'iPhone',
  IdentitySystem.ipad => 'iPad',
  IdentitySystem.other => '',
};

/// The name of an identity as lists show it: "Firefox on Windows", the
/// name of one of the user's own, "Default"... [choice] is a choice from
/// the settings or what the engine reports for a tab.
String identityName(AppL10n l, String choice, List<CustomIdentity> custom) {
  switch (choice) {
    case Identities.defaultId:
      return l.identityDefault;
    case Identities.defaultDesktopId:
      return l.identityOn('Chrome', 'Linux');
    case Identities.randomPhone:
      return l.identityRandomPhone;
    case Identities.randomComputer:
      return l.identityRandomComputer;
    case Identities.randomAny:
      return l.identityRandomAny;
    case 'safari-ipad':
      return l.identityOn('Safari', 'iPad');
  }
  final CustomIdentity? own = Identities.custom(choice, custom);
  if (own != null) return own.name;
  final IdentityPreset? p = Identities.preset(choice);
  if (p == null) return l.identityDefault;
  // The names don't depend on the version.
  final IdentitySpec s = p.spec(DateTime.utc(2026));
  return l.identityOn(_browserName(s.browser), _systemName(s.system));
}

/// Settings > Browser identity (B42): the identity for all sites, sites
/// with their own, and the user's own identities.
class IdentityPage extends ConsumerWidget {
  const IdentityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final ThemeData theme = Theme.of(context);
    final BrowserSettings s = ref.watch(browserSettingsProvider);
    final BrowserData data = ref.read(browserDataProvider);
    final DeviceIdentity device =
        ref.watch(deviceIdentityProvider).value ?? const DeviceIdentity();
    final String global = Identities.known(s.identity, s.customIdentities);
    final List<MapEntry<String, String>> rules =
        s.identityRules.entries.toList()..sort(
          (MapEntry<String, String> a, MapEntry<String, String> b) =>
              a.key.compareTo(b.key),
        );
    final bool usesRandom =
        Identities.randoms.contains(global) ||
        s.identityRules.values.any(Identities.randoms.contains);

    BrowserSettings now() => ref.read(browserSettingsProvider);

    Future<void> pickGlobal() async {
      final String? choice = await showIdentityPicker(
        context,
        title: l.identityAllSites,
        selected: global,
        custom: s.customIdentities,
      );
      if (choice != null) {
        await data.saveSettings(now().copyWith(identity: choice));
      }
    }

    Future<void> setRule(String host, String? choice) => data.saveSettings(
      now().copyWith(
        identityRules: <String, String>{
          for (final MapEntry<String, String> e in now().identityRules.entries)
            if (e.key != host) e.key: e.value,
          host: ?choice,
        },
      ),
    );

    Future<void> pickRule(String host, String selected) async {
      final String? choice = await showIdentityPicker(
        context,
        title: host,
        selected: selected,
        custom: now().customIdentities,
      );
      if (choice != null) await setRule(host, choice);
    }

    Future<void> addSite() async {
      final String? host = await _askHost(context);
      if (host == null || !context.mounted) return;
      await pickRule(host, now().identityRules[host] ?? global);
    }

    Future<void> editOwn(CustomIdentity? existing) async {
      final CustomIdentity? saved = await Navigator.of(context)
          .push<CustomIdentity>(
            MaterialPageRoute<CustomIdentity>(
              fullscreenDialog: true,
              builder: (_) => IdentityEditorPage(existing: existing),
            ),
          );
      if (saved == null) return;
      await data.saveSettings(
        now().copyWith(
          customIdentities: <CustomIdentity>[
            for (final CustomIdentity c in now().customIdentities)
              if (c.id == saved.id) saved else c,
            if (existing == null) saved,
          ],
        ),
      );
    }

    Future<void> deleteOwn(CustomIdentity c) async {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext d) => AlertDialog(
          title: Text(l.identityDeleteQ(c.name)),
          content: Text(l.identityDeleteExplain),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text(l.delete),
            ),
          ],
        ),
      );
      if (ok != true) return;
      final String choice = Identities.customChoice(c.id);
      final BrowserSettings before = now();
      await data.saveSettings(
        before.copyWith(
          identity: before.identity == choice ? Identities.defaultId : null,
          identityRules: <String, String>{
            for (final MapEntry<String, String> e
                in before.identityRules.entries)
              if (e.value != choice) e.key: e.value,
          },
          customIdentities: <CustomIdentity>[
            for (final CustomIdentity x in before.customIdentities)
              if (x.id != c.id) x,
          ],
        ),
      );
    }

    Widget header(String text) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l.identity)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(l.identityExplain),
          ),
          header(l.identityAllSites),
          ListTile(
            key: const ValueKey<String>('identity-global'),
            leading: const Icon(Icons.badge_outlined),
            title: Text(identityName(l, global, s.customIdentities)),
            subtitle: switch (global) {
              Identities.defaultId => Text(l.identityDefaultSub),
              _ when Identities.randoms.contains(global) => Text(
                l.identityRandomSub,
              ),
              _ => null,
            },
            trailing: const Icon(Icons.arrow_drop_down),
            onTap: pickGlobal,
          ),
          _SeenCard(choice: global, custom: s.customIdentities, device: device),
          if (usesRandom)
            ListTile(
              leading: const Icon(Icons.shuffle),
              title: Text(l.identityShuffle),
              onTap: () async {
                final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
                await ref.read(browserEngineProvider).shuffleIdentity();
                m.showSnackBar(SnackBar(content: Text(l.identityShuffled)));
              },
            ),
          header(l.identitySites),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l.identitySitesExplain,
              style: theme.textTheme.bodySmall,
            ),
          ),
          for (final MapEntry<String, String> e in rules)
            ListTile(
              leading: const Icon(Icons.public),
              title: Text(e.key, textDirection: TextDirection.ltr),
              subtitle: Text(
                identityName(
                  l,
                  Identities.known(e.value, s.customIdentities),
                  s.customIdentities,
                ),
              ),
              onTap: () => pickRule(
                e.key,
                Identities.known(e.value, s.customIdentities),
              ),
              trailing: IconButton(
                tooltip: l.remove,
                icon: const Icon(Icons.close),
                onPressed: () => setRule(e.key, null),
              ),
            ),
          ListTile(
            key: const ValueKey<String>('identity-add-site'),
            leading: const Icon(Icons.add),
            title: Text(l.identityAddSite),
            onTap: addSite,
          ),
          header(l.identityOwn),
          for (final CustomIdentity c in s.customIdentities)
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(c.name),
              subtitle: Text(
                c.userAgent,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
              ),
              onTap: () => editOwn(c),
              trailing: IconButton(
                tooltip: l.delete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => deleteOwn(c),
              ),
            ),
          ListTile(
            key: const ValueKey<String>('identity-make-own'),
            leading: const Icon(Icons.add),
            title: Text(l.identityMakeOwn),
            onTap: () => editOwn(null),
          ),
        ],
      ),
    );
  }

  static Future<String?> _askHost(BuildContext context) =>
      showDialog<String>(context: context, builder: (_) => const _HostDialog());
}

/// Asks for a site's address; pops with its host (no "www."), or null.
class _HostDialog extends StatefulWidget {
  const _HostDialog();

  @override
  State<_HostDialog> createState() => _HostDialogState();
}

class _HostDialogState extends State<_HostDialog> {
  // Owned here, so it lives until the dialog has finished closing.
  final TextEditingController _host = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  void _done() {
    final String? h = cleanHostRule(_host.text);
    if (h == null) {
      setState(() => _error = context.l10n.notAHost);
      return;
    }
    Navigator.pop(context, h.startsWith('www.') ? h.substring(4) : h);
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    return AlertDialog(
      title: Text(l.identityAddSite),
      // Scrolls, so a small screen with the keyboard open still fits it.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l.identityAddSiteExplain),
            const SizedBox(height: 8),
            TextField(
              controller: _host,
              autofocus: true,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'example.com',
                errorText: _error,
              ),
              onSubmitted: (_) => _done(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TextButton(onPressed: _done, child: Text(l.next)),
      ],
    );
  }
}

/// "What sites are told" for [choice]: the user agent as it goes out, and
/// what the Client Hints say.
class _SeenCard extends StatelessWidget {
  const _SeenCard({
    required this.choice,
    required this.custom,
    required this.device,
  });

  final String choice;
  final List<CustomIdentity> custom;
  final DeviceIdentity device;

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final ThemeData theme = Theme.of(context);
    final IdentitySpec? spec = Identities.spec(choice, custom, DateTime.now());
    final bool random = Identities.randoms.contains(choice);
    final String userAgent = random
        ? ''
        : device.fill(spec?.userAgent ?? device.defaultUserAgent);
    final String hints = random
        ? l.identitySeenRandom
        : !device.clientHints
        ? l.identityHintsOld
        : spec == null
        ? l.identityHintsSame('Google Chrome ${device.chrome}'.trim())
        : spec.hasClientHints
        ? l.identityHintsSame(
            device.fill('${spec.hints.brand} ${spec.hints.brandVersion}'),
          )
        : l.identityHintsNone;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l.identitySeen, style: theme.textTheme.labelLarge),
            if (userAgent.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SelectableText(
                  userAgent,
                  key: const ValueKey<String>('identity-seen-ua'),
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(hints, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// A sheet to pick an identity; gives the choice (see `Identities`), or
/// null when closed.
Future<String?> showIdentityPicker(
  BuildContext context, {
  required String title,
  required String selected,
  required List<CustomIdentity> custom,
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext sheet) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(sheet).height * 0.8,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            title,
            style: Theme.of(sheet).textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: IdentityChoices(
              selected: selected,
              custom: custom,
              onPicked: (String v) => Navigator.of(sheet).pop(v),
            ),
          ),
        ),
      ],
    ),
  ),
);

/// The list of identities to pick from, in groups.
class IdentityChoices extends StatelessWidget {
  const IdentityChoices({
    super.key,
    required this.selected,
    required this.custom,
    required this.onPicked,
    this.settingsName,
  });

  final String selected;
  final List<CustomIdentity> custom;
  final ValueChanged<String> onPicked;

  /// With this, "Same as Settings" comes first, and names what that is.
  final String? settingsName;

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final ThemeData theme = Theme.of(context);

    Widget header(String text) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 24, 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );

    Widget tile(String value, {String? subtitle, bool ltr = false}) =>
        RadioListTile<String>(
          key: ValueKey<String>('identity-choice-$value'),
          value: value,
          title: Text(
            value == _asSettings
                ? l.identityAsSettings
                : identityName(l, value, custom),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: ltr ? TextDirection.ltr : null,
                ),
        );

    return RadioGroup<String>(
      groupValue: selected,
      onChanged: (String? v) {
        if (v != null) onPicked(v);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (settingsName != null) tile(_asSettings, subtitle: settingsName),
          tile(Identities.defaultId, subtitle: l.identityDefaultSub),
          if (custom.isNotEmpty) header(l.identityOwn),
          for (final CustomIdentity c in custom)
            tile(
              Identities.customChoice(c.id),
              subtitle: c.userAgent,
              ltr: true,
            ),
          header(l.identityPhones),
          for (final IdentityPreset p in Identities.presets)
            if (p.kind != IdentityKind.computer) tile(p.id),
          header(l.identityComputers),
          for (final IdentityPreset p in Identities.presets)
            if (p.kind == IdentityKind.computer) tile(p.id),
          header(l.identityRandom),
          for (final String r in Identities.randoms) tile(r),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: Text(l.identityRandomSub, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// From the page menu: the identity for this tab, or for this site every
/// time. Picking one applies it and loads the page again.
Future<void> showTabIdentitySheet(
  BuildContext context,
  WidgetRef ref,
  BrowserTab tab,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext sheet) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(sheet).height * 0.8,
    ),
    child: _TabIdentitySheet(tab: tab),
  ),
);

class _TabIdentitySheet extends ConsumerStatefulWidget {
  const _TabIdentitySheet({required this.tab});

  final BrowserTab tab;

  @override
  ConsumerState<_TabIdentitySheet> createState() => _TabIdentitySheetState();
}

class _TabIdentitySheetState extends ConsumerState<_TabIdentitySheet> {
  /// False: this tab only. True: this site, every time.
  bool _site = false;

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final ThemeData theme = Theme.of(context);
    final BrowserSettings s = ref.watch(browserSettingsProvider);
    final BrowserTab tab =
        ref.watch(
          tabsProvider.select((TabsState t) => t.byId(widget.tab.id)),
        ) ??
        widget.tab;
    final String host = hostOf(tab.url);
    final String? rule = s.identityRules[host];
    final String global = Identities.known(s.identity, s.customIdentities);
    final String selected = _site
        ? (rule == null
              ? _asSettings
              : Identities.known(rule, s.customIdentities))
        : (tab.identity == null
              ? _asSettings
              : Identities.known(tab.identity, s.customIdentities));

    Future<void> pick(String choice) async {
      final NavigatorState nav = Navigator.of(context);
      final String? value = choice == _asSettings ? null : choice;
      if (_site) {
        final BrowserSettings now = ref.read(browserSettingsProvider);
        await ref
            .read(browserDataProvider)
            .saveSettings(
              now.copyWith(
                identityRules: <String, String>{
                  for (final MapEntry<String, String> e
                      in now.identityRules.entries)
                    if (e.key != host) e.key: e.value,
                  host: ?value,
                },
              ),
            );
      } else {
        await ref.read(tabsProvider.notifier).setIdentity(tab.id, value);
      }
      nav.pop();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(l.identity, style: theme.textTheme.titleLarge),
        ),
        if (host.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SegmentedButton<bool>(
              key: const ValueKey<String>('identity-scope'),
              showSelectedIcon: false,
              segments: <ButtonSegment<bool>>[
                ButtonSegment<bool>(
                  value: false,
                  label: Text(l.identityThisTab),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text(l.identityThisSite),
                ),
              ],
              selected: <bool>{_site},
              onSelectionChanged: (Set<bool> v) =>
                  setState(() => _site = v.first),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Text(
            _site ? l.identityThisSiteSub(host) : l.identityThisTabSub,
            style: theme.textTheme.bodySmall,
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: IdentityChoices(
              selected: selected,
              custom: s.customIdentities,
              settingsName: identityName(l, global, s.customIdentities),
              onPicked: pick,
            ),
          ),
        ),
      ],
    );
  }
}

/// Makes or changes one of the user's own identities: a name and a user
/// agent string, with what the browser works out from it shown live.
/// Pops with the identity to save.
class IdentityEditorPage extends ConsumerStatefulWidget {
  const IdentityEditorPage({super.key, this.existing});

  final CustomIdentity? existing;

  @override
  ConsumerState<IdentityEditorPage> createState() => _IdentityEditorPageState();
}

class _IdentityEditorPageState extends ConsumerState<IdentityEditorPage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _ua = TextEditingController(
    text: widget.existing?.userAgent ?? '',
  );
  bool _tried = false;

  @override
  void dispose() {
    _name.dispose();
    _ua.dispose();
    super.dispose();
  }

  String? _problem(AppL10n l) => switch (checkUserAgent(_ua.text)) {
    null => null,
    UserAgentProblem.empty => l.identityUaEmpty,
    UserAgentProblem.tooLong => l.identityUaTooLong,
    UserAgentProblem.notAscii => l.identityUaNotAscii,
  };

  /// Fills the string in from one of the browsers in the list.
  Future<void> _startFrom(DeviceIdentity device) async {
    final AppL10n l = context.l10n;
    final String? id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheet) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              title: Text(l.identityOn('Chrome', 'Android')),
              onTap: () => Navigator.of(sheet).pop(Identities.defaultId),
            ),
            for (final IdentityPreset p in Identities.presets)
              ListTile(
                title: Text(identityName(l, p.id, const <CustomIdentity>[])),
                onTap: () => Navigator.of(sheet).pop(p.id),
              ),
          ],
        ),
      ),
    );
    if (id == null || !mounted) return;
    final String text = id == Identities.defaultId
        ? device.defaultUserAgent
        : device.fill(Identities.preset(id)!.userAgent(DateTime.now()));
    setState(() {
      _ua.text = text;
      if (_name.text.trim().isEmpty) {
        _name.text = id == Identities.defaultId
            ? l.identityOn('Chrome', 'Android')
            : identityName(l, id, const <CustomIdentity>[]);
      }
    });
  }

  void _save() {
    final AppL10n l = context.l10n;
    setState(() => _tried = true);
    if (_problem(l) != null) return;
    final String ua = cleanUserAgent(_ua.text);
    final String name = _name.text.trim();
    Navigator.of(context).pop(
      CustomIdentity(
        id: widget.existing?.id ?? newItemId(),
        name: name.isEmpty ? _fallbackName(l, ua) : name,
        userAgent: ua,
      ),
    );
  }

  /// A name for an identity saved without one.
  static String _fallbackName(AppL10n l, String ua) {
    final IdentitySpec s = IdentitySpec.fromUserAgent('', ua);
    final String browser = _browserName(s.browser);
    final String system = _systemName(s.system);
    if (browser.isEmpty) return ua.length > 40 ? '${ua.substring(0, 40)}…' : ua;
    return system.isEmpty ? browser : l.identityOn(browser, system);
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final ThemeData theme = Theme.of(context);
    final DeviceIdentity device =
        ref.watch(deviceIdentityProvider).value ?? const DeviceIdentity();
    final String? problem = _problem(l);
    final IdentitySpec? spec = problem == null
        ? IdentitySpec.fromUserAgent('', _ua.text)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? l.identityNew : l.identityEdit),
        leading: IconButton(
          tooltip: l.cancel,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      // The buttons are part of the body, so they stay above the keyboard.
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: <Widget>[
                  TextField(
                    key: const ValueKey<String>('identity-name'),
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: l.name),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey<String>('identity-ua'),
                    controller: _ua,
                    minLines: 3,
                    maxLines: 6,
                    keyboardType: TextInputType.visiblePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      labelText: l.identityUserAgent,
                      alignLabelWithHint: true,
                      helperText: l.identityUserAgentHelp('{chrome}'),
                      helperMaxLines: 3,
                      errorText: _tried ? problem : null,
                      errorMaxLines: 2,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: const ValueKey<String>('identity-start-from'),
                      onPressed: () => _startFrom(device),
                      icon: const Icon(Icons.playlist_add),
                      label: Text(l.identityStartFrom),
                    ),
                  ),
                  if (spec != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Text(
                      l.identityWorkedOut,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Row(
                      l.identityBrowserRow,
                      spec.browser == IdentityBrowser.other
                          ? l.identityUnknown
                          : '${_browserName(spec.browser)} '
                                    '${device.fill(spec.version)}'
                                .trim(),
                    ),
                    _Row(
                      l.identitySystemRow,
                      spec.system == IdentitySystem.other
                          ? l.identityUnknown
                          : _systemName(spec.system),
                    ),
                    _Row(
                      l.identityHintsRow,
                      spec.hasClientHints
                          ? device.fill(
                              '${spec.hints.brand} ${spec.hints.brandVersion}, '
                              '${spec.hints.platform}',
                            )
                          : l.identityHintsRowNone,
                    ),
                    if (spec.platform != null)
                      _Row('navigator.platform', spec.platform!),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey<String>('identity-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey<String>('identity-save'),
                      onPressed: _save,
                      child: Text(l.save),
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

/// A label and its value on one line of the editor's preview.
class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 132, child: Text(label, style: text.bodySmall)),
          Expanded(
            child: Text(
              value,
              style: text.bodyMedium,
              textDirection: TextDirection.ltr,
              textAlign: Directionality.of(context) == TextDirection.rtl
                  ? TextAlign.right
                  : TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }
}
