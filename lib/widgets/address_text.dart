import 'package:flutter/material.dart';

/// A web address. Addresses read left to right in every language, so in
/// Hebrew the text keeps its order and only sits on the right-hand side.
class AddressText extends StatelessWidget {
  const AddressText(this.address, {super.key, this.style, this.maxLines = 1});

  final String address;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return Text(
      address,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textDirection: TextDirection.ltr,
      textAlign: rtl ? TextAlign.right : TextAlign.left,
      style: style,
    );
  }
}
