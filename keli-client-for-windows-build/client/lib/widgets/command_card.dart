import 'package:flutter/material.dart';

import '../theme.dart';

/// The shared shell every PUSH capability view uses: a FULL-SCREEN panel with a title bar + close
/// button and a body slot that fills the rest. New views wrap their content in a CommandCard so they
/// all look and behave the same. The body child is given the full remaining space (an [Expanded]); the
/// view is responsible for scrolling its own content if it can overflow.
class CommandCard extends StatelessWidget {
  const CommandCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    required this.onClose,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KeliTheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title bar — bold, full-width, with a big close target for the wall tablet.
            Container(
              decoration: BoxDecoration(
                color: KeliTheme.surface2,
                border: Border(bottom: BorderSide(color: KeliTheme.edge)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
              child: Row(
                children: [
                  Icon(icon, color: KeliTheme.accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(color: KeliTheme.text, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: Icon(Icons.close, color: KeliTheme.text, size: 26),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
