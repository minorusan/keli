import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/incoming_command.dart';
import '../theme.dart';
import '../widgets/command_card.dart';

/// View for the `show_image` capability: a base64 image in a closable window.
/// Pinch/double-tap to zoom (Instagram-style) inline; tap to open full-screen.
/// Reads data['data'] (base64, optionally a data: URI), data['title'], data['caption'].
class ShowImageView extends StatelessWidget {
  const ShowImageView({super.key, required this.command, required this.onClose});

  final IncomingCommand command;
  final VoidCallback onClose;

  Uint8List? _decode() {
    final raw = command.str('data');
    final b64 = raw.contains(',') ? raw.substring(raw.indexOf(',') + 1) : raw; // strip data: URI prefix
    try {
      return base64Decode(b64.trim());
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _decode();
    final title = command.str('title').trim();
    final caption = command.str('caption').trim();
    return CommandCard(
      title: title.isNotEmpty ? title : 'Image',
      icon: Icons.image_outlined,
      onClose: onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The image fills the full-screen body; pinch to zoom inline, tap to open the immersive viewer.
          Expanded(
            child: bytes != null
                ? GestureDetector(
                    onTap: () => _openFullscreen(context, bytes),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
                      ),
                    ),
                  )
                : Center(child: Text('invalid image data', style: TextStyle(color: KeliTheme.danger))),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Text(caption, textAlign: TextAlign.center, style: TextStyle(color: KeliTheme.muted, fontSize: 13.5)),
            ),
        ],
      ),
    );
  }

  void _openFullscreen(BuildContext context, Uint8List bytes) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => _FullscreenImage(bytes: bytes),
      ),
    );
  }
}

/// Full-screen black backdrop with a freely zoomable/pannable image (like Instagram).
class _FullscreenImage extends StatelessWidget {
  const _FullscreenImage({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 8,
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            right: 4,
            child: IconButton(
              icon: Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
