import 'package:flutter/material.dart';

class DiscardGuard extends StatelessWidget {
  const DiscardGuard({super.key, required this.dirty, required this.child});

  final bool dirty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Buang perubahan?'),
            content: const Text('Perubahan yang belum disimpan akan hilang.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Tetap di sini')),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Buang')),
            ],
          ),
        );
        if (discard == true) navigator.pop();
      },
      child: child,
    );
  }
}
