import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../a11y/announce.dart';
import '../analytics/usage_tracker.dart';
import '../theme/app_colors.dart';

enum VoiceFailure { unavailable, permissionDenied, noMatch, other }

abstract interface class VoiceInput {
  Future<bool> start({
    required void Function(String text, bool done) onText,
    required void Function(VoiceFailure failure) onError,
  });
  Future<void> stop();
}

class DeviceVoiceInput implements VoiceInput {
  DeviceVoiceInput([SpeechToText? speech]) : _speech = speech ?? SpeechToText();
  final SpeechToText _speech;
  void Function(VoiceFailure)? _onError;

  VoiceFailure _map(SpeechRecognitionError e) => switch (e.errorMsg) {
    'error_permission' ||
    'error_insufficient_permissions' => VoiceFailure.permissionDenied,
    'error_no_match' || 'error_speech_timeout' => VoiceFailure.noMatch,
    'error_language_not_supported' ||
    'error_language_unavailable' ||
    'error_server_disconnected' ||
    'error_network' ||
    'error_server' => VoiceFailure.unavailable,
    _ => VoiceFailure.other,
  };

  @override
  Future<bool> start({
    required void Function(String text, bool done) onText,
    required void Function(VoiceFailure failure) onError,
  }) async {
    _onError = onError;
    final ok = await _speech.initialize(
      onError: (e) => _onError?.call(_map(e)),
    );
    if (!ok) {
      onError(VoiceFailure.unavailable);
      return false;
    }
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) =>
          onText(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        onDevice: true,
        partialResults: true,
        listenMode: ListenMode.dictation,
        localeId: 'id_ID',
        cancelOnError: true,
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(seconds: 60),
      ),
    );
    return true;
  }

  @override
  Future<void> stop() => _speech.stop();
}

final voiceInputProvider = Provider<VoiceInput>((ref) => DeviceVoiceInput());

String voiceFailureText(VoiceFailure f) => switch (f) {
  VoiceFailure.unavailable =>
    'Dikte di perangkat belum tersedia. Unduh bahasa Indonesia untuk pengenalan suara offline di pengaturan ponsel, lalu coba lagi.',
  VoiceFailure.permissionDenied =>
    'Izin mikrofon ditolak. Izinkan mikrofon untuk beOkay di pengaturan ponsel.',
  VoiceFailure.noMatch =>
    'Suara tidak terdengar jelas. Coba lagi lebih dekat ke ponsel.',
  VoiceFailure.other => 'Dikte berhenti. Coba lagi.',
};

class MicButton extends ConsumerStatefulWidget {
  const MicButton({
    super.key,
    required this.controller,
    required this.domain,
    this.enabled = true,
    this.onChanged,
  });
  final TextEditingController controller;
  final String domain;
  final bool enabled;
  final VoidCallback? onChanged;
  @override
  ConsumerState<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends ConsumerState<MicButton> {
  bool listening = false;
  String prefix = '';

  Future<void> toggle() async {
    final voice = ref.read(voiceInputProvider);
    if (listening) {
      await voice.stop();
      if (mounted) setState(() => listening = false);
      return;
    }
    final current = widget.controller.text.trim();
    prefix = current.isEmpty ? '' : '$current ';
    setState(() => listening = true);
    announce(context, 'Mendengarkan. Diproses di perangkat.');
    var tracked = false;
    final started = await voice.start(
      onText: (text, done) {
        if (!mounted) return;
        widget.controller.text = '$prefix$text'.trimLeft();
        widget.controller.selection = TextSelection.collapsed(
          offset: widget.controller.text.length,
        );
        widget.onChanged?.call();
        if (!tracked && text.isNotEmpty) {
          tracked = true;
          ref
              .read(usageTrackerProvider)
              .track(
                'voice_input_used',
                domain: widget.domain,
                meta: {'via': 'voice'},
              );
        }
        if (done) setState(() => listening = false);
      },
      onError: (f) {
        if (!mounted) return;
        setState(() => listening = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(voiceFailureText(f))));
      },
    );
    if (!started && mounted) setState(() => listening = false);
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: listening
        ? 'Selesai bicara'
        : 'Dikte dengan suara (diproses di perangkat)',
    onPressed: widget.enabled ? toggle : null,
    style: IconButton.styleFrom(
      backgroundColor: listening ? AppColors.brandTint : AppColors.surface,
      side: BorderSide(color: listening ? AppColors.brand : AppColors.border),
      fixedSize: const Size(48, 48),
    ),
    icon: Icon(
      listening ? Icons.stop_rounded : Icons.mic_none_rounded,
      color: AppColors.brand,
    ),
  );
}
