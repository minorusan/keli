import 'package:flutter/material.dart';

import '../config.dart';
import 'draggable_window.dart';

/// Floating, draggable live **Tapo minimap** (roomba-rnd `:9113` `/minimap`), anchored top-right.
/// Present every session; position not persisted. See [DraggableWindow].
class TapoMapWindow extends StatelessWidget {
  const TapoMapWindow({super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableWindow(
      title: 'TAPO MAP',
      icon: Icons.map_outlined,
      corner: WindowCorner.topRight,
      child: RefreshingImage(
        urlBuilder: (t) => '$kRobotMapUrl/minimap?t=$t',
        interval: const Duration(seconds: 2),
        fit: BoxFit.contain,
        offline: 'no map signal',
      ),
    );
  }
}
