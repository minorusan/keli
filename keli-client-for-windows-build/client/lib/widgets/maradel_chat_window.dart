import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../services/maradel_session.dart';
import '../theme.dart';
import 'draggable_window.dart';

/// Floating, draggable, READ-ONLY mirror of the live Maradel session — our text, Maradel's replies,
/// and her tool calls. Mirrors the Tapo cam window (top-right, opposite the cam). No input: sending
/// stays on the FAB → `/send` path. Data comes from [MaradelSession] (`GET /session` + `session:*`).
class MaradelChatWindow extends StatelessWidget {
  const MaradelChatWindow({super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableWindow(
      title: 'MARADEL',
      icon: Icons.chat_bubble_outline,
      corner: WindowCorner.topRight,
      width: 300,
      height: 360,
      child: _ChatBody(),
    );
  }
}

class _ChatBody extends StatefulWidget {
  const _ChatBody();

  @override
  State<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends State<_ChatBody> {
  final _scroll = ScrollController();

  void _toBottom() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MaradelSession>(
      builder: (_, s, _) {
        if (s.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No active Maradel session yet.\nIt will appear here as you talk.',
                textAlign: TextAlign.center,
                style: TextStyle(color: KeliTheme.muted, fontSize: 12),
              ),
            ),
          );
        }
        _toBottom(); // keep pinned to the newest as messages/tools stream in
        final msgs = s.messages;
        final pending = s.pendingTools;
        return ListView(
          controller: _scroll,
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          children: [
            for (final m in msgs) _MessageBlock(message: m),
            // In-progress assistant turn: tools that arrived before the reply text.
            if (pending.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.only(left: 4, top: 2, bottom: 2),
                child: Text('Maradel is working…',
                    style: TextStyle(color: KeliTheme.muted, fontSize: 10, fontStyle: FontStyle.italic)),
              ),
              for (final t in pending) _ToolCard(tool: t),
            ],
          ],
        );
      },
    );
  }
}

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({required this.message});
  final SessionMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == SessionRole.user;
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        if (message.content.trim().isNotEmpty)
          Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: EdgeInsets.symmetric(vertical: 3),
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              constraints: BoxConstraints(maxWidth: 230),
              decoration: BoxDecoration(
                color: isUser ? KeliTheme.surface2 : KeliTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: isUser ? null : Border.all(color: KeliTheme.accent.withValues(alpha: 0.25)),
              ),
              child: isUser
                  ? Text(message.content, style: TextStyle(color: KeliTheme.text, fontSize: 12))
                  : MarkdownBody(
                      data: message.content,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(color: KeliTheme.text, fontSize: 12),
                        code: TextStyle(color: KeliTheme.accentBright, fontSize: 11, backgroundColor: KeliTheme.surface2),
                        listBullet: TextStyle(color: KeliTheme.text, fontSize: 12),
                        a: TextStyle(color: KeliTheme.accent),
                      ),
                    ),
            ),
          ),
        // Tool cards belong to the assistant turn.
        for (final t in message.tools) _ToolCard(tool: t),
      ],
    );
  }
}

class _ToolCard extends StatefulWidget {
  const _ToolCard({required this.tool});
  final ToolCall tool;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tool;
    final (chipColor, chipText) = switch (t.status) {
      'succeeded' => (KeliTheme.accent, 'done'),
      'failed' => (KeliTheme.danger, 'failed'),
      _ => (KeliTheme.muted, 'running…'),
    };
    return Container(
      margin: EdgeInsets.symmetric(vertical: 3),
      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      constraints: BoxConstraints(maxWidth: 250),
      decoration: BoxDecoration(
        color: KeliTheme.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KeliTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.build_circle_outlined, size: 13, color: KeliTheme.accent),
              SizedBox(width: 5),
              Flexible(
                child: Text(t.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: KeliTheme.text, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              SizedBox(width: 6),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(chipText, style: TextStyle(color: chipColor, fontSize: 9, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (t.input.trim().isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 3),
              child: Text(t.input,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: KeliTheme.muted, fontSize: 10, fontStyle: FontStyle.italic)),
            ),
          if (t.notes.trim().isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 3),
              child: Text(t.notes, style: TextStyle(color: KeliTheme.muted, fontSize: 10)),
            ),
          if (t.output.trim().isNotEmpty) ...[
            SizedBox(height: 3),
            GestureDetector(
              onTap: () => setState(() => _open = !_open),
              child: Row(
                children: [
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 14, color: KeliTheme.accentDim),
                  Text(_open ? 'hide output' : 'show output',
                      style: TextStyle(color: KeliTheme.accentDim, fontSize: 10)),
                ],
              ),
            ),
            if (_open)
              Container(
                width: double.infinity,
                margin: EdgeInsets.only(top: 3),
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(color: KeliTheme.bg, borderRadius: BorderRadius.circular(6)),
                child: Text(t.output, style: TextStyle(color: KeliTheme.text, fontSize: 10)),
              ),
          ],
        ],
      ),
    );
  }
}
