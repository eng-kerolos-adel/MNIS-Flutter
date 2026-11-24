import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A patient photo supporting live webcam JPEG/PNG data-URIs as well as HTTPS URLs,
/// falling back to a plain person icon when no verified photo is on file yet.
class PatientAvatar extends StatelessWidget {
  final String? url;
  final double size;
  final BorderRadius borderRadius;
  const PatientAvatar({
    super.key,
    required this.url,
    this.size = 64,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  Uint8List? _tryDecodeDataUri(String raw) {
    final comma = raw.indexOf(',');
    if (comma < 0 || comma + 1 >= raw.length) return null;
    try {
      return base64Decode(raw.substring(comma + 1).trim());
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      color: cs.surfaceContainerHigh,
      child: Icon(Icons.person, color: cs.onSurfaceVariant, size: size * 0.55),
    );
    if (url == null || url!.isEmpty) {
      return ClipRRect(borderRadius: borderRadius, child: placeholder);
    }
    if (url!.startsWith('data:image/')) {
      final bytes = _tryDecodeDataUri(url!);
      if (bytes == null) {
        return ClipRRect(borderRadius: borderRadius, child: placeholder);
      }
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
        ),
      );
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }
}


