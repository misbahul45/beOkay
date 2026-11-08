import 'package:flutter/material.dart';
import 'app_text_field.dart';

class RecordReasonDialog extends StatefulWidget {
  const RecordReasonDialog({super.key, required this.restoring});
  final bool restoring;
  @override
  State<RecordReasonDialog> createState() => _RecordReasonDialogState();
}

class _RecordReasonDialogState extends State<RecordReasonDialog> {
  final reason = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.restoring ? 'Pulihkan catatan?' : 'Arsipkan catatan?'),
    content: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Versi lama tetap tersimpan. Perubahan ini memengaruhi ringkasan harian.',
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Alasan perubahan',
            controller: reason,
            maxLength: 300,
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Isi alasan perubahan.' : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      TextButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, reason.text.trim());
          }
        },
        child: const Text('Konfirmasi'),
      ),
    ],
  );
}
