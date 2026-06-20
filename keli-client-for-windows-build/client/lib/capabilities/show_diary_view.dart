import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
          mainAxisSize: MainAxisSize.min,
          children: [
            const TabBar(
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(text: 'Diary'),
                Tab(text: 'Claude'),
              ],
            ),
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: TabBarView(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: MarkdownBody(data: content),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: MarkdownBody(
                      data: claudeActivity ?? 'No recent activity.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}