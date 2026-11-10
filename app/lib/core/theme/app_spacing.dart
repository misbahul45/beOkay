import 'package:flutter/painting.dart';

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double page = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
  static const double huge = 48;
  static const double giant = 64;
  static const double minTouchTarget = 48;
  static const double buttonHeight = 48;
  static const double fieldHeight = 48;
  static const double cardPadding = 14;
  static const double chipHeight = 36;
  static const double navHeight = 64;
}

abstract final class AppRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double hero = 28;
  static const double input = sm;
  static const double card = lg;
  static const double sheet = hero;
  static const double chip = 18;
  static const double pill = 999;

  static BorderRadius get inputRadius => BorderRadius.circular(input);
  static BorderRadius get cardRadius => BorderRadius.circular(card);
  static BorderRadius get pillRadius => BorderRadius.circular(pill);
}

abstract final class AppShadows {
  static const List<BoxShadow> soft = [
    BoxShadow(color: Color(0x1018252A), blurRadius: 20, offset: Offset(0, 6)),
  ];
}
