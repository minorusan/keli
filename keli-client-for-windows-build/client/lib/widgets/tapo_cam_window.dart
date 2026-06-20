import 'package:flutter/material.dart';

import '../config.dart';
import 'draggable_window.dart';

/// Floating, draggable live **Tapo camera** feed (roomba-rnd `:9110` `/cam.jpg`), anchored top-left.
/// Refreshes fast (~3 fps) for a near-live view. Present every session; position not persisted.
class TapoCamWindow extends StatelessWidget {
  const TapoCamWindow({super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableWindow(
      title: 'TAPO CAM',
      icon: Icons.videocam_outlined,
      corner: WindowCorner.topLeft,
      width: 280,
      height: 188, // ~16:9 under the 32px header
      child: RefreshingImage(
        urlBuilder: (t) => '$kRobotCamUrl/cam.jpg?$t',
        interval: const Duration(milliseconds: 350),
        fit: BoxFit.cover,
        offline: 'camera offline',
      ),
    );
  }
}
