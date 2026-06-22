import 'package:flutter/material.dart';

import '../models/incoming_command.dart';
import '../widgets/command_card.dart';
import 'front_flashlight_view.dart';
import 'input_string_view.dart';
import 'rear_flashlight_view.dart';
import 'show_image_view.dart';
import 'show_text_view.dart';
import 'show_diary_view.dart';
import 'take_photo_view.dart';

/// The capability registry — the ONE place the Flutter app learns what it can do.
/// Two kinds:
///   • PUSH      (machine → phone): show something; appears as a closable window.
///   • REQUEST   (machine asks → phone answers): an interactive popup that returns a result.
/// Event names MUST match the backend (`capabilities.ts` / `requests.ts`). Adding either kind is a
/// view widget + one line here — the connection auto-subscribes and the home screen auto-renders.

// ── push capabilities (closable windows) ─────────────────────────────────────
typedef CommandViewBuilder = Widget Function(BuildContext context, IncomingCommand command, VoidCallback onClose);

final Map<String, CommandViewBuilder> kCommandViews = {
  'show_text': (ctx, cmd, onClose) => ShowTextView(command: cmd, onClose: onClose),
  'show_image': (ctx, cmd, onClose) => ShowImageView(command: cmd, onClose: onClose),
  'show_diary': (ctx, cmd, onClose) => ShowDiaryView(
        title: '${cmd.data['title'] ?? ''}',
        // Tolerate alternate field names from the backend; the diary text has shown up empty / as a bare
        // "[keli_show_diary]" tool-marker when the expected `content` field wasn't populated.
        content: _firstNonEmpty([cmd.data['content'], cmd.data['text'], cmd.data['body'], cmd.data['entry']]) ?? '',
        claudeActivity: _firstNonEmpty([cmd.data['claude_activity'], cmd.data['claudeActivity'], cmd.data['claude']]),
        onClose: onClose,
      ),
};

List<String> pushEvents() => kCommandViews.keys.toList();

/// First value that is real text — skips nulls, blanks, and bare tool-markers like `[keli_show_diary]`
/// (which the backend has sent in place of the actual content). Returns null if none qualify.
String? _firstNonEmpty(List<Object?> values) {
  final marker = RegExp(r'^\[[a-z0-9_]+\]$', caseSensitive: false);
  for (final v in values) {
    final s = '${v ?? ''}'.trim();
    if (s.isEmpty || marker.hasMatch(s)) continue;
    return s;
  }
  return null;
}

Widget buildCommandView(BuildContext context, IncomingCommand command, VoidCallback onClose) {
  final builder = kCommandViews[command.event];
  if (builder != null) return builder(context, command, onClose);
  return CommandCard(
    title: command.event,
    icon: Icons.help_outline,
    onClose: onClose,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: SelectableText('${command.data}', style: const TextStyle(fontSize: 13)),
    ),
  );
}

// ── request capabilities (interactive, awaitable, return a result) ────────────
/// A view calls this exactly once to finish the request (early return or on its own timer).
typedef RequestComplete = void Function({required bool ok, Map<String, dynamic>? data, String? reason});
typedef RequestViewBuilder = Widget Function(BuildContext context, IncomingCommand command, RequestComplete complete);

final Map<String, RequestViewBuilder> kRequestViews = {
  'input_string': (ctx, cmd, complete) => InputStringView(command: cmd, complete: complete),
  'take_photo': (ctx, cmd, complete) => TakePhotoView(command: cmd, complete: complete),
  'front_flashlight': (ctx, cmd, complete) => FrontFlashlightView(command: cmd, complete: complete),
  'rear_flashlight': (ctx, cmd, complete) => RearFlashlightView(command: cmd, complete: complete),
};

List<String> requestEvents() => kRequestViews.keys.toList();

Widget buildRequestView(BuildContext context, IncomingCommand command, RequestComplete complete) {
  final builder = kRequestViews[command.event];
  if (builder != null) return builder(context, command, complete);
  // Unknown request kind — complete it as failed so the machine isn't left hanging.
  complete(ok: false, data: null, reason: 'unsupported request: ${command.event}');
  return const SizedBox.shrink();
}
