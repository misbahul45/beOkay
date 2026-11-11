import 'package:flutter/material.dart';

import '../router/routes.dart';
import '../theme/app_colors.dart';

/// Identity and navigation target for each health domain.
///
/// One definition keeps icon, label, colour and route consistent on Today, Log and Insights.
/// Colour is never the only signal: each domain also has its own icon and label.
class DomainStyle {
  const DomainStyle({
    required this.key,
    required this.label,
    required this.icon,
    required this.listRoute,
    required this.addRoute,
    required this.tint,
    required this.ink,
    this.listOnly = false,
  });

  final String key;
  final String label;
  final IconData icon;
  final String listRoute;
  final String addRoute;
  final Color tint;
  final Color ink;

  /// Medication and goals have no per-event detail page; their event opens the owning list.
  final bool listOnly;

  /// Route to the original record, used by Timeline tiles.
  String detailRoute(String recordId) =>
      listOnly ? listRoute : '$listRoute/$recordId';

  static DomainStyle get meal => DomainStyle(
    key: 'meal',
    label: 'Makanan',
    icon: Icons.restaurant_outlined,
    listRoute: Routes.meals,
    addRoute: Routes.addMeal,
    tint: AppColors.mealTint,
    ink: AppColors.mealInk,
  );
  static DomainStyle get glucose => DomainStyle(
    key: 'glucose',
    label: 'Glukosa',
    icon: Icons.water_drop_outlined,
    listRoute: Routes.glucose,
    addRoute: Routes.addGlucose,
    tint: AppColors.glucoseTint,
    ink: AppColors.glucoseInk,
  );
  static DomainStyle get activity => DomainStyle(
    key: 'activity',
    label: 'Aktivitas',
    icon: Icons.directions_walk_rounded,
    listRoute: Routes.activities,
    addRoute: Routes.addActivity,
    tint: AppColors.activityTint,
    ink: AppColors.activityInk,
  );
  static DomainStyle get medication => DomainStyle(
    key: 'medication',
    label: 'Obat',
    icon: Icons.medication_outlined,
    listRoute: Routes.medications,
    addRoute: Routes.addMedication,
    tint: AppColors.medicationTint,
    ink: AppColors.medicationInk,
    listOnly: true,
  );
  static DomainStyle get goal => DomainStyle(
    key: 'goal',
    label: 'Tujuan',
    icon: Icons.flag_outlined,
    listRoute: Routes.goals,
    addRoute: Routes.addGoal,
    tint: AppColors.goalTint,
    ink: AppColors.goalInk,
    listOnly: true,
  );

  static List<DomainStyle> get all => [
    meal,
    glucose,
    activity,
    medication,
    goal,
  ];

  static DomainStyle of(String domain) =>
      all.firstWhere((style) => style.key == domain, orElse: () => meal);
}
