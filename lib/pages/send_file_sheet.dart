import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';

/// Where "Send to" took a file.
sealed class SendTarget {
  const SendTarget();
}

class SendToNotes extends SendTarget {
  const SendToNotes();
}

class SendToDevice extends SendTarget {
  const SendToDevice(this.device);
  final DeviceTabs device;
}

/// B40: "Send to" for a download or a file in the vault: ZT Notes (the
/// file goes into a new note, which ZT Notes encrypts), or another of the
/// account's devices (an end-to-end encrypted attachment that only its ZT
/// Browser can open).
///
/// [readBytes] reads the file when it is at most the given size, else
/// null; [toNotes] hands it to ZT Notes.
Future<void> showSendFileSheet(
  BuildContext context,
  WidgetRef ref, {
  required String name,
  required String mime,
  required int size,
  required Future<Uint8List?> Function(int max) readBytes,
  required Future<SendResult> Function() toNotes,
}) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppL10n l = context.l10n;
  const int max = ZtAttachments.defaultMaxBytes;
  final bool tooBig = size > max;
  final SendTarget? to = await showModalBottomSheet<SendTarget>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext sheet) => Consumer(
      builder: (BuildContext context, WidgetRef ref, _) {
        final AsyncValue<List<DeviceTabs>> devices = ref.watch(
          otherDevicesProvider,
        );
        final List<DeviceTabs> list = devices.value ?? const <DeviceTabs>[];
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    l.sendFileTitle(name),
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ListTile(
                  key: const ValueKey<String>('send-to-notes'),
                  leading: const Icon(Icons.sticky_note_2_outlined),
                  title: Text(l.sendToNotes),
                  subtitle: Text(l.sendToNotesSub),
                  onTap: () => Navigator.pop(sheet, const SendToNotes()),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Text(
                    l.sendToDevice,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (devices.isLoading && list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: Text(l.sendToDeviceNone),
                  )
                else
                  for (final DeviceTabs d in list)
                    ListTile(
                      enabled: !tooBig,
                      leading: const Icon(Icons.devices_outlined),
                      title: Text(d.deviceName),
                      subtitle: Text(
                        tooBig ? l.fileTooBigToSend : l.sendFileEncrypted,
                      ),
                      onTap: () => Navigator.pop(sheet, SendToDevice(d)),
                    ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    ),
  );
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  switch (to) {
    case null:
      return;
    case SendToNotes():
      switch (await toNotes()) {
        case SendResult.sent:
          return;
        case SendResult.notInstalled:
          say(l.notesNotInstalled);
        case SendResult.unsupported:
          say(l.notesCantTakeFile);
        case SendResult.missing:
          say(l.fileGone);
        case SendResult.failed:
          say(l.couldntSend);
      }
    case SendToDevice(:final DeviceTabs device):
      say(l.sendingFile(name));
      try {
        final Uint8List? bytes = await readBytes(max);
        if (bytes == null) {
          say(l.fileTooBigToSend);
          return;
        }
        await ref
            .read(browserDataProvider)
            .sendFile(device, bytes, name: name, mime: mime);
        say(l.sentFileToDevice(name, device.deviceName));
      } on AttachmentTooLarge {
        say(l.fileTooBigToSend);
      } on Object {
        say(l.couldntSend);
      }
  }
}
