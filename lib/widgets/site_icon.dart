import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zerotrust_browser/browser/address.dart';

/// A site's favicon, or its first letter in a tinted circle.
class SiteIcon extends StatelessWidget {
  const SiteIcon({super.key, required this.url, this.favicon, this.size = 32});

  final String? url;
  final Uint8List? favicon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Uint8List? icon = favicon;
    if (icon != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 4),
        child: Image.memory(
          icon,
          width: size,
          height: size,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _letter(scheme),
        ),
      );
    }
    return _letter(scheme);
  }

  Widget _letter(ColorScheme scheme) {
    final String host = hostOf(url);
    final String letter = host.isEmpty ? '•' : host[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.45,
        ),
      ),
    );
  }
}
