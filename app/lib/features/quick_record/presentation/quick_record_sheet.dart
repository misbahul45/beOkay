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
              ListTile(
                leading: const Icon(Icons.water_drop_outlined),
                title: const Text('Glukosa'),
                subtitle: const Text('Hasil glukometer dan konteks pengukuran'),
                onTap: () {
                  Navigator.pop(sheet);
                  context.push(Routes.addGlucose);
                },
              ),
              ListTile(
                leading: const Icon(Icons.directions_walk),
                title: const Text('Aktivitas'),
                subtitle: const Text(
                  'Sesi, durasi, dan intensitas yang kamu rasakan',
                ),
                onTap: () {
                  Navigator.pop(sheet);
                  context.push(Routes.addActivity);
                },
              ),
              const ListTile(
                enabled: false,
                leading: Icon(Icons.medication_outlined),
                title: Text('Konsumsi obat'),
                subtitle: Text('Belum tersedia'),
              ),
            ],
          ),
        ),
      ),
    );
