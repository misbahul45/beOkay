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
    this.background,
    this.onRefresh,
  });

  final List<Widget> children;
  final String? title;
  final VoidCallback? onBack;
  final bool showBack;
  final Widget? bottom;
  final List<Widget>? actions;
  final Color? background;

  /// When set, the page supports pull-to-refresh.
  final Future<void> Function()? onRefresh;

  Widget _withRefresh(Widget scroll) => onRefresh == null
      ? scroll
      : RefreshIndicator(
          color: AppColors.primary,
          onRefresh: onRefresh!,
          child: scroll,
        );

  @override
  Widget build(BuildContext context) {
    final background = this.background ?? AppColors.background;
    final canGoBack = showBack && (onBack != null || context.canPop());
    // Tab roots without title/actions skip the empty app bar and use the space for content.
    final hasBar = canGoBack || title != null || (actions?.isNotEmpty ?? false);
    return Scaffold(
      backgroundColor: background,
      appBar: !hasBar
          ? null
          : AppBar(
              backgroundColor: background,
              automaticallyImplyLeading: false,
              toolbarHeight: 52,
              leadingWidth: AppSpacing.page + 40,
              leading: canGoBack
                  ? Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.page - 4),
                      child: IconButton(
                        tooltip: 'Kembali',
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surface,
                          side: BorderSide(color: AppColors.border),
                          fixedSize: const Size(40, 40),
                          minimumSize: const Size(40, 40),
                          tapTargetSize: MaterialTapTargetSize.padded,
                        ),
                        onPressed:
                            onBack ?? () => Navigator.of(context).maybePop(),
                      ),
                    )
                  : null,
              title: title == null ? null : Text(title!),
              actions: actions,
            ),
      body: SafeArea(
        top: !hasBar,
        bottom: bottom == null,
        child: _withRefresh(
          SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: onRefresh == null
                ? null
                : const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              hasBar ? AppSpacing.xs : AppSpacing.md,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.xs,
                  AppSpacing.page,
                  AppSpacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [bottom!],
                ),
              ),
            ),
    );
  }
}
