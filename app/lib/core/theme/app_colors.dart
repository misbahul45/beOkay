import 'package:flutter/painting.dart';

import '../../beokay_tokens.dart';

abstract final class AppColors {
  static const Color background = BeOkayColor.offWhite;
  static const Color surface = BeOkayColor.white;
  static const Color surfaceMuted = BeOkayColor.surface2;
  static const Color accent = BeOkayColor.iceBlue;
  static const Color border = BeOkayColor.line;
  static const Color overlay = BeOkayColor.steelBlue;

  static const Color primary = BeOkayColor.charcoal;
  static const Color onPrimary = BeOkayColor.white;
  static const Color textPrimary = BeOkayColor.charcoal;
  static const Color textSecondary = BeOkayColor.slateText;
  static const Color decorative = BeOkayColor.slate;
  static const Color disabled = BeOkayColor.steelBlue;

  static const Color errorBackground = BeOkayColor.coralBg;
  static const Color errorForeground = BeOkayColor.coralText;
  static const Color warningBackground = BeOkayColor.amberBg;
  static const Color warningForeground = BeOkayColor.amberText;
  static const Color infoBackground = BeOkayColor.iceBlue;
  static const Color infoForeground = BeOkayColor.charcoal;
  static const Color focus = BeOkayColor.charcoal;
}
