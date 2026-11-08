import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_typography.dart';

Future<void> showQuickRecord(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Apa yang ingin kamu catat?', style: AppTypography.heading),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.restaurant_outlined),
                title: const Text('Makanan'),
                subtitle: const Text('Makanan, porsi, dan catatanmu'),
                onTap: () {
                  Navigator.pop(sheet);
                  context.push(Routes.addMeal);
                },
              ),
              for (final item in [
                (Icons.water_drop_outlined, 'Glukosa'),
                (Icons.directions_walk, 'Aktivitas'),
                (Icons.medication_outlined, 'Konsumsi obat'),
              ])
                ListTile(
                  enabled: false,
                  leading: Icon(item.$1),
                  title: Text(item.$2),
                  subtitle: const Text('Belum tersedia'),
                ),
            ],
          ),
        ),
      ),
    );
