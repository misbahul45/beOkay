import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.children,
    this.title,
    this.onBack,
    this.showBack = true,
    this.bottom,
    this.actions,
    this.background = AppColors.background,
  });

  final List<Widget> children;
  final String? title;
  final VoidCallback? onBack;
  final bool showBack;
  final Widget? bottom;
  final List<Widget>? actions;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final canGoBack = showBack && (onBack != null || context.canPop());
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        automaticallyImplyLeading: false,
        leadingWidth: AppSpacing.page + 48,
        leading: canGoBack
            ? Padding(
                padding: const EdgeInsets.only(left: AppSpacing.page - 8),
                child: IconButton(
                  tooltip: 'Kembali',
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.border),
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                ),
              )
            : null,
        title: title == null ? null : Text(title!),
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        bottom: bottom == null,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.md),
                child: Column(mainAxisSize: MainAxisSize.min, children: [bottom!]),
              ),
            ),
    );
  }
}
