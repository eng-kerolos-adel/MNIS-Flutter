import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_typography.dart';
import '../utils/error_messages.dart';

/// Standard loading / error / data handling for an [AsyncValue], with a
/// shimmer skeleton on loading and a retry button on error.
class AsyncValueView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  final bool isAr;
  final double loadingHeight;

  const AsyncValueView({
    super.key,
    required this.value,
    required this.builder,
    required this.isAr,
    this.onRetry,
    this.loadingHeight = 240,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return value.when(
      data: (d) => builder(context, d),
      loading: () => Shimmer.fromColors(
        baseColor: isDark
            ? cs.surfaceContainerHigh.withOpacity(0.55)
            : cs.surfaceContainerHigh.withOpacity(0.7),
        highlightColor: isDark
            ? cs.surfaceContainerHighest.withOpacity(0.85)
            : cs.surfaceContainerLowest,
        child: Container(
          height: loadingHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      error: (err, st) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: cs.outline),
            const SizedBox(height: 10),
            Text(
              friendlyError(err, isAr: isAr),
              style:
                  AppTypography.bodyMd.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(isAr ? 'إعادة المحاولة' : 'Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Simple centered "nothing here yet" placeholder for empty lists.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: cs.secondary),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: AppTypography.bodyMd.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

