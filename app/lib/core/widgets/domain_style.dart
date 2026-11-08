import 'package:flutter/material.dart';

import '../router/routes.dart';

/// Visual identity and navigation target for each health domain.
///
/// One definition keeps icon, label and route consistent on Today, Log and
/// Insights, so a domain never looks different between screens.
class DomainStyle {
  const DomainStyle({required this.key, required this.label, required this.icon, required this.listRoute, required this.addRoute});

  final String key;
  final String label;
  final IconData icon;
  final String listRoute;
  final String addRoute;

  /// Route to the original record, used by Timeline tiles.
  String detailRoute(String recordId) => '$listRoute/$recordId';

  static const meal = DomainStyle(key: 'meal', label: 'Makanan', icon: Icons.restaurant_outlined, listRoute: Routes.meals, addRoute: Routes.addMeal);
  static const glucose = DomainStyle(key: 'glucose', label: 'Glukosa', icon: Icons.water_drop_outlined, listRoute: Routes.glucose, addRoute: Routes.addGlucose);
  static const activity = DomainStyle(key: 'activity', label: 'Aktivitas', icon: Icons.directions_walk_rounded, listRoute: Routes.activities, addRoute: Routes.addActivity);

  static const all = [meal, glucose, activity];

  static DomainStyle of(String domain) => all.firstWhere((style) => style.key == domain, orElse: () => meal);
}
