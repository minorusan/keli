import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/incoming_command.dart';
import '../theme.dart';
import '../widgets/command_card.dart';

/// View for the `show_text` capability: a closable markdown window.
/// Reads `data['text']` (markdown) and `data['title']`.
class ShowTextView extends StatelessWidget {
  const ShowTextView({super.key, required this.command, required this.onClose});

  final IncomingCommand command;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final title = command.str('title').trim();
    return CommandCard(
      title: title.isNotEmpty ? title : 'Message',
      icon: Icons.notifications_active_outlined,
      onClose: onClose,
      child: MarkdownBody(
        data: command.str('text'),
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: const TextStyle(color: KeliTheme.text, fontSize: 14, height: 1.5),
          h1: const TextStyle(color: KeliTheme.text, fontSize: 20, fontWeight: FontWeight.bold),
          h2: const TextStyle(color: KeliTheme.text, fontSize: 17, fontWeight: FontWeight.bold),
          code: const TextStyle(color: KeliTheme.accent, backgroundColor: KeliTheme.bg, fontFamily: 'monospace'),
          codeblockDecoration: BoxDecoration(color: KeliTheme.bg, borderRadius: BorderRadius.circular(8)),
          blockquoteDecoration: const BoxDecoration(border: Border(left: BorderSide(color: KeliTheme.accentDim, width: 3))),
          a: const TextStyle(color: KeliTheme.accent, decoration: TextDecoration.underline),
        ),
        onTapLink: (text, href, title) {
          if (href != null) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
        },
      ),
    );
  }
}
