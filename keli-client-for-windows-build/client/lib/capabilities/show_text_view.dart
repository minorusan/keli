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
      // Fills the full-screen body; scrolls when the message is long. Centred + width-capped so long
      // prose stays readable on a wide landscape wall tablet.
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: MarkdownBody(
              data: command.str('text'),
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(color: KeliTheme.text, fontSize: 16, height: 1.55),
                h1: TextStyle(color: KeliTheme.text, fontSize: 24, fontWeight: FontWeight.bold),
                h2: TextStyle(color: KeliTheme.text, fontSize: 20, fontWeight: FontWeight.bold),
                code: TextStyle(color: KeliTheme.accent, backgroundColor: KeliTheme.bg, fontFamily: 'monospace'),
                codeblockDecoration: BoxDecoration(color: KeliTheme.bg, borderRadius: BorderRadius.circular(8)),
                blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: KeliTheme.accentDim, width: 3))),
                a: TextStyle(color: KeliTheme.accent, decoration: TextDecoration.underline),
              ),
              onTapLink: (text, href, title) {
                if (href != null) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
              },
            ),
          ),
        ),
      ),
    );
  }
}
