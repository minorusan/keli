import 'dart:async';

import 'package:flutter/material.dart';

import '../models/incoming_command.dart';
import '../theme.dart';
import 'registry.dart';

/// Interactive view for the `input_string` request: a popup with a text field and a Send button.
/// The user types and presses Send (early return); if the timer (data['timeoutMs'], default 30 s)
/// runs out first, it completes as a timeout. Returns { text }.
class InputStringView extends StatefulWidget {
  const InputStringView({super.key, required this.command, required this.complete});

  final IncomingCommand command;
  final RequestComplete complete;

  @override
  State<InputStringView> createState() => _InputStringViewState();
}

class _InputStringViewState extends State<InputStringView> {
  final TextEditingController _controller = TextEditingController();
  Timer? _ticker;
  int _remaining = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final ms = (widget.command.data['timeoutMs'] as num?)?.toInt() ?? 30000;
    _remaining = (ms / 1000).ceil();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) _finish(ok: false, reason: 'timeout');
    });
  }

  void _finish({required bool ok, Map<String, dynamic>? data, String? reason}) {
    if (_done) return;
    _done = true;
    _ticker?.cancel();
    widget.complete(ok: ok, data: data, reason: reason);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prompt = widget.command.str('prompt').trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Material(
          color: KeliTheme.surface,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.keyboard_outlined, color: KeliTheme.accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(prompt.isNotEmpty ? prompt : 'Enter text',
                          style: const TextStyle(color: KeliTheme.text, fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                    Text('${_remaining}s', style: const TextStyle(color: KeliTheme.muted, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  style: const TextStyle(color: KeliTheme.text),
                  minLines: 1,
                  maxLines: 4,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: KeliTheme.bg,
                    hintText: 'Type here…',
                    hintStyle: const TextStyle(color: KeliTheme.muted),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _finish(ok: false, reason: 'cancelled'),
                      child: const Text('Cancel', style: TextStyle(color: KeliTheme.muted)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: KeliTheme.accent, foregroundColor: KeliTheme.bg),
                      onPressed: _send,
                      child: const Text('Send'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _send() => _finish(ok: true, data: {'text': _controller.text});
}
