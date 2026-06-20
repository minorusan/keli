import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/incoming_command.dart';
import '../theme.dart';
import 'registry.dart';

/// Interactive view for the `take_photo` request: opens the front/back camera with a Take button
/// and a countdown (data['timeoutMs'], default 5 s). The user taps Take (early return), or it
/// auto-captures when the timer ends. Returns { image (base64 JPEG), camera }.
class TakePhotoView extends StatefulWidget {
  const TakePhotoView({super.key, required this.command, required this.complete});

  final IncomingCommand command;
  final RequestComplete complete;

  @override
  State<TakePhotoView> createState() => _TakePhotoViewState();
}

class _TakePhotoViewState extends State<TakePhotoView> {
  CameraController? _controller;
  Timer? _ticker;
  int _remaining = 0;
  bool _done = false;
  bool _ready = false;
  String? _error;

  String get _which => widget.command.str('camera') == 'back' ? 'back' : 'front';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      if (!await Permission.camera.request().isGranted) {
        _finish(ok: false, reason: 'camera permission denied');
        return;
      }
      final cams = await availableCameras();
      final want = _which == 'back' ? CameraLensDirection.back : CameraLensDirection.front;
      final cam = cams.firstWhere((c) => c.lensDirection == want, orElse: () => cams.first);
      final controller = CameraController(cam, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
      final ms = (widget.command.data['timeoutMs'] as num?)?.toInt() ?? 5000;
      _remaining = (ms / 1000).ceil();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _remaining--);
        if (_remaining <= 0) _capture();
      });
    } catch (e) {
      _finish(ok: false, reason: 'camera error: $e');
    }
  }

  Future<void> _capture() async {
    if (_done) return;
    _done = true;
    _ticker?.cancel();
    try {
      final file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      widget.complete(ok: true, data: {'image': base64Encode(bytes), 'camera': _which});
    } catch (e) {
      widget.complete(ok: false, data: null, reason: 'capture failed: $e');
    }
  }

  void _finish({required bool ok, String? reason}) {
    if (_done) return;
    _done = true;
    _ticker?.cancel();
    widget.complete(ok: ok, data: null, reason: reason);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: KeliTheme.danger)));
    }
    if (!_ready || _controller == null) {
      return const Center(child: CircularProgressIndicator(color: KeliTheme.accent));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(aspectRatio: 3 / 4, child: CameraPreview(_controller!)),
            ),
            const SizedBox(height: 14),
            Text('$_which camera · auto in ${_remaining}s',
                style: const TextStyle(color: KeliTheme.muted, fontSize: 12)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _finish(ok: false, reason: 'cancelled'),
                  child: const Text('Cancel', style: TextStyle(color: KeliTheme.muted)),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: KeliTheme.accent, foregroundColor: KeliTheme.bg),
                  onPressed: _capture,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
