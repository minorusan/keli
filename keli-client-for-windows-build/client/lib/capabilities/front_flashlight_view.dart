import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../models/incoming_command.dart';
import 'registry.dart';

/// Interactive view for the `front_flashlight` request: a FULL-SCREEN WHITE panel at max screen
/// brightness — the screen as a flashlight — for data['timeoutMs'] (default 30 s) or until tapped to
/// cancel. Used to light a front-camera photo in the dark. Restores brightness on the way out.
class FrontFlashlightView extends StatefulWidget {
  const FrontFlashlightView({super.key, required this.command, required this.complete});

  final IncomingCommand command;
  final RequestComplete complete;

  @override
  State<FrontFlashlightView> createState() => _FrontFlashlightViewState();
}

class _FrontFlashlightViewState extends State<FrontFlashlightView> {
  Timer? _ticker;
  int _remaining = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _boost();
    final ms = (widget.command.data['timeoutMs'] as num?)?.toInt() ?? 30000;
    _remaining = (ms / 1000).ceil();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) _finish('timeout');
    });
  }

  Future<void> _boost() async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(1.0);
    } catch (_) {/* brightness control unavailable — the white screen still helps */}
  }

  Future<void> _restore() async {
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {/* ignore */}
  }

  void _finish(String reason) {
    if (_done) return;
    _done = true;
    _ticker?.cancel();
    _restore();
    widget.complete(ok: reason == 'done' || reason == 'timeout', data: {'reason': reason}, reason: reason);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _restore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _finish('done'),
      child: Container(
        color: Colors.white,
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flashlight_on, color: Colors.black54, size: 28),
            const SizedBox(height: 8),
            Text('Front light on · ${_remaining}s', style: const TextStyle(color: Colors.black54, fontSize: 14)),
            const Text('tap to turn off', style: TextStyle(color: Colors.black38, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
