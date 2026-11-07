import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../network/api_exception.dart';
import '../theme/tokens.dart';

/// Einheitliche Darstellung von Laden, Fehlern (inkl. Netzwerkfehlern) und Daten.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.builder, this.onRetry, this.loading});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: builder,
      loading: () => loading ?? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      error: (e, _) => ErrorView(error: e, onRetry: onRetry),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry, this.compact = false});
  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final isNet = error is ApiException && (error as ApiException).isNetwork;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? DSpacing.l : DSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isNet ? Icons.cloud_off_rounded : Icons.error_outline_rounded, size: 48, color: DColors.textMuted),
            const SizedBox(height: DSpacing.m),
            Text(isNet ? s.errorNetworkTitle : s.errorGenericTitle, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: DSpacing.s),
            Text(errorText(error), style: const TextStyle(color: DColors.textMuted), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: DSpacing.l),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: Text(s.retry)),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: DColors.primary.withValues(alpha: 0.8)),
            const SizedBox(height: DSpacing.l),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: DSpacing.s),
              Text(message!, style: const TextStyle(color: DColors.textMuted), textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: DSpacing.l), action!],
          ],
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
