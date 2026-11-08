import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../network/api_exception.dart';
import '../router/routes.dart';
import 'async_body.dart';
import 'info_card.dart';
import 'pill_button.dart';

class HealthError extends StatelessWidget {
  const HealthError({super.key, required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) =>
      error is ApiException &&
          (error as ApiException).code == 'CONSENT_REQUIRED'
      ? InfoCard(
          title: 'Persetujuan diperlukan',
          text: 'Tinjau persetujuan untuk mengakses data ini.',
          action: PillButton(
            label: 'Kelola persetujuan',
            onPressed: () => context.push(Routes.consentManagement),
          ),
        )
      : ErrorState(error: error, onRetry: retry);
}
