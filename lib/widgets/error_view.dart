import 'package:flutter/material.dart';

import '../odoo/rpc.dart';

class ErrorView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;

  const ErrorView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  factory ErrorView.fromError(Object error, {Key? key, required VoidCallback onRetry}) {
    final network = error is OdooException && error.isNetwork;
    return ErrorView(
      key: key,
      icon: network ? Icons.cloud_off : Icons.error_outline,
      title: network ? 'Connection problem' : "Couldn't load this page",
      message: error is OdooException ? error.message : 'Something went wrong. Try again.',
      onRetry: onRetry,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
