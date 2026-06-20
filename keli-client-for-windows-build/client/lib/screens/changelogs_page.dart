import 'package:flutter/material.dart';

import '../changelog.dart';
import '../config.dart';
import '../theme.dart';

/// The full per-build changelog history (newest first; the current build is highlighted yellow).
/// Tap an entry to read its formatted changelog.
class ChangelogsPage extends StatelessWidget {
  const ChangelogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KeliTheme.bg,
      appBar: AppBar(
        backgroundColor: KeliTheme.surface,
        title: const Text('Changelogs', style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w700)),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: kChangelog.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final e = kChangelog[i];
          final current = e.build == kAppBuild;
          return Material(
            color: current ? const Color(0xFF2A2A12) : KeliTheme.surface,
            borderRadius: BorderRadius.circular(10),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: current ? const Color(0xFFE8D44A) : KeliTheme.surface2),
              ),
              title: Text('${e.title}  ·  v${e.version}',
                  style: TextStyle(
                      color: current ? const Color(0xFFE8D44A) : KeliTheme.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              subtitle: Text('build ${e.build} · ${e.date}${current ? '  · current' : ''}',
                  style: const TextStyle(color: KeliTheme.muted, fontSize: 11.5)),
              trailing: const Icon(Icons.chevron_right, color: KeliTheme.muted),
              onTap: () => showChangelogDialog(context, e),
            ),
          );
        },
      ),
    );
  }
}
