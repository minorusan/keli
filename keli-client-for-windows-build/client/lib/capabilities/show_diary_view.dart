import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme.dart';
import '../widgets/command_card.dart';

class ShowDiaryView extends StatelessWidget {
  final String title;
  final String content;
  final String? claudeActivity;
  final VoidCallback onClose;

  const ShowDiaryView({
    super.key,
    required this.title,
    required this.content,
    this.claudeActivity,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return CommandCard(
      title: title,
      icon: Icons.book,
      onClose: onClose,
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            TabBar(
              labelColor: KeliTheme.accent,
              unselectedLabelColor: KeliTheme.muted,
              indicatorColor: KeliTheme.accent,
              tabs: const [
                Tab(text: 'Diary'),
                Tab(text: 'Claude'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _page(content),
                  _page(claudeActivity ?? 'No recent activity.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page(String md) => Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: MarkdownBody(
              data: md,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(color: KeliTheme.text, fontSize: 15, height: 1.5),
                h1: TextStyle(color: KeliTheme.text, fontSize: 22, fontWeight: FontWeight.bold),
                h2: TextStyle(color: KeliTheme.text, fontSize: 18, fontWeight: FontWeight.bold),
                a: TextStyle(color: KeliTheme.accent),
                code: TextStyle(color: KeliTheme.accent, backgroundColor: KeliTheme.bg, fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
      );
}