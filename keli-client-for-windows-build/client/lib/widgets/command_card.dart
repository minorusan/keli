import 'package:flutter/material.dart';

import '../theme.dart';

/// The shared shell every capability view uses: a titled card with a close
/// button and a body slot. New views wrap their content in a CommandCard so
/// they all look and behave the same — this is the "established template".
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
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      color: KeliTheme.surface,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: KeliTheme.surface2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: KeliTheme.surface2,
            padding: EdgeInsets.fromLTRB(14, 8, 6, 8),
            child: Row(
              children: [
                Icon(icon, color: KeliTheme.accent, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(color: KeliTheme.text, fontSize: 14, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: Icon(Icons.close, color: KeliTheme.muted, size: 20),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: child,
          ),
        ],
      ),
    );
  }
}
