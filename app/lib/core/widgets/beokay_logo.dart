import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class BeOkayLogo extends StatelessWidget {
  const BeOkayLogo({super.key, this.height, this.width});

  final double? height;
  final double? width;

  static const _light = 'assets/images/logo_full.png';
  static const _dark = 'assets/images/logo_full_dark.png';

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    return Image.asset(
      dark ? _dark : _light,
      height: height,
      width: width,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'beOkay',
    );
  }
}
