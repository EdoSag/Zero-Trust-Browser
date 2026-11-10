import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zerotrust_browser/browser/address.dart';

/// A page's address as a QR code, to open it on another phone by pointing
/// its camera at the screen. Made on this phone; nothing is sent anywhere.
Future<void> showQrSheet(BuildContext context, String url, String title) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(sheet).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            // Dark on white whatever the theme: scanners need contrast.
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: QrImageView(
                data: url,
                size: 240,
                backgroundColor: Colors.white,
                semanticsLabel: 'QR code for $url',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              displayAddress(url),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(sheet).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.pop(sheet);
                SharePlus.instance.share(
                  ShareParams(uri: Uri.tryParse(url), subject: title),
                );
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share link'),
            ),
          ],
        ),
      ),
    ),
  );
}
