import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';

/// "Send to your devices" (B23): pick one of the account's other devices;
/// the page shows up there, end-to-end encrypted, the next time it syncs.
Future<void> showSendTabSheet(
  BuildContext context,
  WidgetRef ref, {
  required String url,
  required String title,
}) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppL10n l = context.l10n;
  final DeviceTabs? to = await showModalBottomSheet<DeviceTabs>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheet) => Consumer(
      builder: (BuildContext context, WidgetRef ref, _) {
        final AsyncValue<List<DeviceTabs>> devices = ref.watch(
          otherDevicesProvider,
        );
        final List<DeviceTabs> list = devices.value ?? const <DeviceTabs>[];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  l.sendToDevice,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (devices.isLoading && list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Text(l.sendToDeviceNone),
                )
              else
                for (final DeviceTabs d in list)
                  ListTile(
                    leading: const Icon(Icons.devices_outlined),
                    title: Text(d.deviceName),
                    subtitle: Text(l.lastActive(_ago(l, d.updatedAt))),
                    onTap: () => Navigator.pop(sheet, d),
                  ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ),
  );
  if (to == null) return;
  try {
    await ref.read(browserDataProvider).sendTab(to, url, title);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.sentToDevice(to.deviceName))));
  } on Object {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.couldntSend)));
  }
}

String _ago(AppL10n l, DateTime at) {
  final Duration d = DateTime.now().difference(at);
  if (d.inDays >= 1) return l.daysAgo(d.inDays);
  if (d.inHours >= 1) return l.hoursAgo(d.inHours);
  return l.justNow;
}
