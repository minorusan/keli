import 'dart:async';

import 'package:flutter/material.dart';
import 'package:torch_light/torch_light.dart';

import '../models/incoming_command.dart';
import '../theme.dart';
import '../widgets/command_card.dart';
import 'registry.dart';

/// Interactive view for the `rear_flashlight` request: turns ON the rear LED torch for
/// data['timeoutMs'] (default 30 s) or until cancelled, with a popup showing it's active. Always
/// turns the torch OFF on finish/dispose. Used to light a rear-camera photo in the dark.
class RearFlashlightView extends StatefulWidget {
  const RearFlashlightView({super.key, required this.command, required this.complete});

  final IncomingCommand command;
  final RequestComplete complete;

  @override
  State<RearFlashlightView> createState() => _RearFlashlightViewState();
}

class _RearFlashlightViewState extends State<RearFlashlightView> {
  Timer? _ticker;
  int _remaining = 0;
  bool _done = false;
  bool _on = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _enable();
  }

  Future<void> _enable() async {
    try {
      await TorchLight.enableTorch();
      if (!mounted) {
        TorchLight.disableTorch();
        return;
      }
      setState(() => _on = true);
      final ms = (widget.command.data['timeoutMs'] as num?)?.toInt() ?? 30000;
      _remaining = (ms / 1000).ceil();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _remaining--);
        if (_remaining <= 0) _finish('timeout');
      });
    } catch (e) {
      _finish('no torch: $e', ok: false);
    }
  }

  Future<void> _off() async {
    try {
      await TorchLight.disableTorch();
    } catch (_) {/* ignore */}
  }

  void _finish(String reason, {bool ok = true}) {
    if (_done) return;
    _done = true;
    _ticker?.cancel();
    _off();
    if (reason.startsWith('no torch')) setState(() => _error = reason);
    widget.complete(ok: ok, data: {'reason': reason}, reason: reason);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _off();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: CommandCard(
          title: 'Rear flashlight',
          icon: Icons.flashlight_on,
          onClose: () => _finish('done'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null)
                Text(_error!, style: const TextStyle(color: KeliTheme.danger, fontSize: 13))
              else
                Row(children: [
                  Icon(_on ? Icons.lightbulb : Icons.lightbulb_outline, color: _on ? KeliTheme.accent : KeliTheme.muted),
                  const SizedBox(width: 8),
                  Text(_on ? 'Torch ON · ${_remaining}s' : 'starting…',
                      style: const TextStyle(color: KeliTheme.text, fontSize: 14)),
                ]),
              const SizedBox(height: 6),
              const Text('tap ✕ to turn off', style: TextStyle(color: KeliTheme.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
