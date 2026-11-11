import 'package:flutter/material.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/widgets/site_icon.dart';

/// Tablets and unfolded foldables (B31): the open tabs side by side above
/// the address bar, like a desktop browser. Shows the tabs of the kind on
/// screen (normal or private).
class TabStrip extends StatefulWidget {
  const TabStrip({
    super.key,
    required this.tabs,
    required this.currentId,
    required this.onSelect,
    required this.onClose,
    required this.onNew,
    required this.onOverview,
  });

  final List<BrowserTab> tabs;
  final String? currentId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final VoidCallback onNew;
  final VoidCallback onOverview;

  static const double height = 44;
  static const double tabWidth = 200;

  @override
  State<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<TabStrip> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(TabStrip old) {
    super.didUpdateWidget(old);
    // A new tab opened at the end: bring it into view.
    if (widget.tabs.length > old.tabs.length &&
        widget.tabs.isNotEmpty &&
        widget.tabs.last.id == widget.currentId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SizedBox(
        height: TabStrip.height,
        child: Row(
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsetsDirectional.only(start: 4, top: 4),
                itemCount: widget.tabs.length,
                itemBuilder: (BuildContext context, int i) {
                  final BrowserTab t = widget.tabs[i];
                  final bool selected = t.id == widget.currentId;
                  return _StripTab(
                    tab: t,
                    selected: selected,
                    onTap: () => widget.onSelect(t.id),
                    onClose: () => widget.onClose(t.id),
                    closeLabel: l.closeTab,
                    startLabel: t.private ? l.privateTab : l.newTab,
                  );
                },
              ),
            ),
            IconButton(
              tooltip: l.newTab,
              icon: const Icon(Icons.add),
              onPressed: widget.onNew,
            ),
            IconButton(
              tooltip: l.tabs,
              icon: const Icon(Icons.grid_view),
              onPressed: widget.onOverview,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _StripTab extends StatelessWidget {
  const _StripTab({
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.onClose,
    required this.closeLabel,
    required this.startLabel,
  });

  final BrowserTab tab;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final String closeLabel;
  final String startLabel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String label = tab.isStartPage ? startLabel : tab.label;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 2),
      child: Material(
        color: selected ? scheme.surface : Colors.transparent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: TabStrip.tabWidth,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 10),
                if (tab.isStartPage)
                  Icon(
                    tab.private ? Icons.privacy_tip_outlined : Icons.public,
                    size: 18,
                  )
                else
                  SiteIcon(url: tab.url, size: 18, favicon: tab.favicon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: closeLabel,
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
