import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_brightness.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/preferences/application/preferences_controller.dart';

class BeOkayApp extends ConsumerWidget {
  const BeOkayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = ref.watch(appBrightnessProvider);
    AppColors.use(brightness);
    final router = ref.watch(routerProvider);
    final preferences = ref.watch(effectivePreferencesProvider);
    return MaterialApp.router(
      title: 'beOkay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(
        brightness: brightness,
        reduceMotion: preferences.reduceMotion,
      ),
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final scale = (media.textScaler.scale(1) * preferences.textSize.scale)
            .clamp(1.0, 2.0);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations:
                  media.disableAnimations || preferences.reduceMotion,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
