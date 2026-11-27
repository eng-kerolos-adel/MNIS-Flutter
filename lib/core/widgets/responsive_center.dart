import 'package:flutter/material.dart';

/// Keeps content gracefully centered and bounded on wide tablets/web screens
/// while occupying full available width smoothly on mobile phones.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = 640,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final inner = padding != null ? Padding(padding: padding!, child: child) : child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: inner),
      ),
    );
  }
}
