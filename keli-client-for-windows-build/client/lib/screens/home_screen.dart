import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';
import 'package:provider/provider.dart';

import '../app_log.dart';
import '../capabilities/registry.dart';
import '../changelog.dart';
import '../config.dart';
import '../models/incoming_command.dart';
import '../services/dynamic_views.dart';
import '../services/voice_player.dart';
import '../services/keli_connection.dart';
import '../services/keli_settings.dart';
import '../services/mic_streamer.dart';
import '../services/unity_bridge.dart';
import '../theme.dart';
import '../widgets/registration_dialog.dart';
import '../widgets/skin_picker.dart';
import '../widgets/draggable_window.dart';
import '../widgets/maradel_chat_window.dart';
import '../widgets/mic_status_bar.dart';
import '../widgets/perception_window.dart';
import '../widgets/update_button.dart';
import '../widgets/widgets_dashboard.dart';
import 'changelogs_page.dart';
import 'gallery_page.dart';
import 'reminders_page.dart';
import 'face_screen.dart';

/// The single screen: connection status in the background, with any open
/// `show_text` windows stacked on top. A side panel holds the updater + info.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  IncomingCommand? _selfAction; // a user-launched action being composed (self-invoke)
  bool _regShown = false; // first-launch registration popup shown this session
  bool _showChat = false; // the floating read-only Maradel chat window (off by default)

  // THE single embedded Unity view. A GlobalKey lets us move it between the full-screen stage and the
  // small corner overlay (during tool popups) WITHOUT reparenting recreating it (Unity stays warm).
  final GlobalKey _faceKey = GlobalKey();
  Widget? _faceCached;
  Widget get _face => _faceCached ??= EmbedUnity(
        key: _faceKey,
        onMessageFromUnity: (message) => context.read<UnityBridge>().onUnityMessage(message),
      );

  // ── dynamic-view content builders (shared between pinned + floating presentations) ──
  Widget _camView() => RefreshingImage(
        urlBuilder: (t) => '$kRobotCamUrl/cam.jpg?$t',
        interval: const Duration(milliseconds: 350),
        fit: BoxFit.cover,
        offline: 'camera offline',
      );

  Widget _mapView() => RefreshingImage(
        urlBuilder: (t) => '$kRobotMapUrl/minimap?t=$t',
        interval: const Duration(seconds: 2),
        fit: BoxFit.contain,
        offline: 'no map signal',
      );

  Widget _viewContent(String id) => switch (id) {
        ViewIds.tapoCam => _camView(),
        ViewIds.tapoMap => _mapView(),
        _ => _face, // unity
      };

  /// The centerpiece: the pinned view, rendered centered. The face keeps its full chrome (avatar
  /// ◀/▶ + name + status); cam/map get a titled frame with quick float/close.
  Widget _pinnedCenter(DynamicViewController views, KeliConnection conn) {
    final id = views.pinnedId;
    if (id == null) return const _EmptyCenter();
    if (id == ViewIds.unity) return _FaceStage(conn: conn, face: _face);
    return _PinnedView(
      id: id,
      onFloat: () => views.float(id),
      onClose: () => views.close(id),
      child: _viewContent(id),
    );
  }

  /// Floating draggable windows for every view in [ViewMode.floating]. The Unity face only floats here
  /// when [faceAt] says so (otherwise it's in the corner / off-screen and must not be double-mounted).
  List<Widget> _floatingViews(DynamicViewController views, _FacePlace faceAt) {
    final out = <Widget>[];
    for (final id in views.floatingIds) {
      if (id == ViewIds.unity && faceAt != _FacePlace.floating) continue;
      final corner = id == ViewIds.tapoCam ? WindowCorner.topLeft : WindowCorner.topRight;
      final (w, h) = switch (id) {
        ViewIds.tapoCam => (280.0, 188.0),
        ViewIds.unity => (240.0, 240.0),
        _ => (260.0, 220.0),
      };
      out.add(DraggableWindow(
        key: ValueKey('float-$id'),
        title: ViewIds.title(id),
        icon: ViewIds.icon(id),
        corner: corner,
        width: w,
        height: h,
        onPin: () => views.pin(id),
        onClose: () => views.close(id),
        child: _viewContent(id),
      ));
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    // First launch after an update → show this build's changelog once.
    WidgetsBinding.instance.addPostFrameCallback((_) => showChangelogIfNew(context));
  }

  // FAB → grid of things the user can launch and send to Maradel.
  void _openActions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KeliTheme.surface,
      isScrollControlled: true, // let it size to content but cap height (landscape-safe)
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        // Responsive columns: wide landscape → more columns → fewer rows → fits the short height.
        final cols = (size.width / 150).floor().clamp(3, 6);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: size.height * 0.85),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Text('Send to Maradel',
                        style: TextStyle(color: KeliTheme.text, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: cols,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.05,
                    physics: NeverScrollableScrollPhysics(),
                    children: [
                      _action(ctx, Icons.keyboard, 'Text', () => _startSelf('input_string', {'prompt': 'Send to Maradel', 'timeoutMs': 300000})),
                      _action(ctx, Icons.camera_front, 'Front', () => _startSelf('take_photo', {'camera': 'front', 'timeoutMs': 15000})),
                      _action(ctx, Icons.camera_rear, 'Rear', () => _startSelf('take_photo', {'camera': 'back', 'timeoutMs': 15000})),
                      _action(ctx, Icons.attach_file, 'File', _pickAndSendFile),
                      _action(ctx, Icons.flashlight_on, 'Front light', () => _startSelf('front_flashlight', {'timeoutMs': 30000})),
                      _action(ctx, Icons.highlight, 'Rear light', () => _startSelf('rear_flashlight', {'timeoutMs': 30000})),
                      _action(ctx, Icons.face_retouching_natural, 'Select skin', () => showSkinPicker(context)),
                      _action(ctx, Icons.sync_alt, 'Bridge → Unity', _openBridge),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _action(BuildContext sheetCtx, IconData icon, String label, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.pop(sheetCtx);
          onTap();
        },
        // Big, glowing tap targets — sized for a wall tablet (feature request: "Bigger buttons on Keli").
        child: Container(
          decoration: BoxDecoration(
            color: KeliTheme.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: KeliTheme.accent.withValues(alpha: 0.35)),
            boxShadow: KeliTheme.glow(blur: 10, alpha: 0.18),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: KeliTheme.accent, size: 46),
              SizedBox(height: 10),
              Text(label, textAlign: TextAlign.center, style: TextStyle(color: KeliTheme.text, fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  void _startSelf(String event, Map<String, dynamic> params) =>
      setState(() => _selfAction = IncomingCommand(event: event, id: 'self', data: params, ts: 0));

  // A self-invoke view finished → send its result to Maradel.
  void _completeSelf({required bool ok, Map<String, dynamic>? data, String? reason}) {
    final action = _selfAction;
    setState(() => _selfAction = null);
    if (!ok || data == null || action == null) return;
    final conn = context.read<KeliConnection>();
    () async {
      bool sent = false;
      if (action.event == 'input_string') {
        final text = (data['text'] as String?)?.trim() ?? '';
        if (text.isNotEmpty) sent = await conn.sendToMaradel(text: text);
      } else if (action.event == 'take_photo') {
        final img = data['image'] as String?;
        if (img != null) {
          sent = await conn.sendToMaradel(attachments: [
            {'kind': 'image', 'mime': 'image/jpeg', 'data': img, 'name': 'photo.jpg'},
          ]);
        }
      }
      _toast(sent ? 'Sent to Maradel' : 'Could not send');
    }();
  }

  Future<void> _pickAndSendFile() async {
    final conn = context.read<KeliConnection>();
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.bytes == null) {
      _toast('Could not read file');
      return;
    }
    final sent = await conn.sendToMaradel(attachments: [
      {'kind': 'file', 'mime': 'application/octet-stream', 'data': base64Encode(f.bytes!), 'name': f.name},
    ]);
    _toast(sent ? 'Sent "${f.name}"' : 'Could not send file');
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // Bridge test: type a string → sent to the embedded Unity (FlutterFace.OnMessage), where it's
  // logged to the Unity console. Replies come back via onMessageFromUnity → the [unity] console log.
  void _openBridge() {
    final ctrl = TextEditingController();
    void send() {
      final t = ctrl.text.trim();
      if (t.isNotEmpty) {
        sendToUnity('FlutterFace', 'OnMessage', t); // flutter_embed_unity
        AppLog.log('bridge', '→unity: $t');
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KeliTheme.surface,
        title: Text('Bridge → Unity', style: TextStyle(color: KeliTheme.accent)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: KeliTheme.text),
          decoration: InputDecoration(
            hintText: 'message → Unity console',
            hintStyle: TextStyle(color: KeliTheme.muted),
          ),
          onSubmitted: (_) {
            send();
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: TextStyle(color: KeliTheme.muted))),
          TextButton(
            onPressed: () {
              send();
              Navigator.pop(ctx);
            },
            child: Text('Send', style: TextStyle(color: KeliTheme.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<KeliConnection>();
    // First launch (no guid stored) → force registration once prefs have loaded.
    final settings = context.watch<KeliSettings>();
    if (settings.ready && !settings.registered && !_regShown) {
      _regShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showRegistrationDialog(context); // dismissible — re-openable from the side panel
      });
    }
    final overlayUp = conn.activeRequest != null || _selfAction != null;
    final views = context.watch<DynamicViewController>();
    // The single warm Unity face goes to exactly ONE place each build: parked off-screen when closed,
    // the corner overlay during a tool popup, the centre when pinned, else its floating window.
    final faceAt = views.isClosed(ViewIds.unity)
        ? _FacePlace.offstage
        : overlayUp
            ? _FacePlace.corner
            : views.isPinned(ViewIds.unity)
                ? _FacePlace.center
                : _FacePlace.floating;
    return Scaffold(
      backgroundColor: Colors.black, // black behind the embedded Unity face
      appBar: AppBar(
        title: Text('Keli', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w700)),
        actions: [
          // Choose the 3D face avatar/skin (asks Unity for the list → searchable picker).
          IconButton(
            tooltip: 'Choose avatar / skin',
            icon: Icon(Icons.face_retouching_natural, color: KeliTheme.accent),
            onPressed: () => showSkinPicker(context),
          ),
          // Toggle the floating read-only Maradel chat window (off by default).
          IconButton(
            tooltip: _showChat ? 'Hide Maradel chat' : 'Show Maradel chat',
            icon: Icon(_showChat ? Icons.chat_bubble : Icons.chat_bubble_outline,
                color: _showChat ? KeliTheme.accent : KeliTheme.muted),
            onPressed: () => setState(() => _showChat = !_showChat),
          ),
          // Widgets dashboard — pin/float/close the dynamic views (face, cam, map).
          IconButton(
            tooltip: 'Widgets',
            icon: Icon(Icons.dashboard_customize_outlined, color: KeliTheme.accent),
            onPressed: () => showWidgetsDashboard(context),
          ),
          // Quick "ears" toggle — stream the mic to Maradel (the robot's ears).
          Consumer<MicStreamer>(
            builder: (_, mic, _) => IconButton(
              tooltip: mic.enabled ? 'Ears on — tap to mute' : 'Ears off — tap to listen',
              icon: Icon(
                mic.enabled ? (mic.connected ? Icons.mic : Icons.mic_external_on) : Icons.mic_off,
                color: mic.enabled
                    ? (mic.connected ? KeliTheme.accent : KeliTheme.danger)
                    : KeliTheme.muted,
              ),
              onPressed: () => context.read<MicStreamer>().setEnabled(!mic.enabled),
            ),
          ),
          if (conn.commands.isNotEmpty)
            IconButton(
              tooltip: 'Close all',
              icon: Icon(Icons.clear_all, color: KeliTheme.accent),
              onPressed: conn.dismissAll,
            ),
        ],
      ),
      endDrawer: _SidePanel(),
      floatingActionButton: (overlayUp || conn.commands.isNotEmpty)
          ? null
          : Container(
              decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: KeliTheme.glow(blur: 12, alpha: 0.5)),
              child: FloatingActionButton.small(
                backgroundColor: KeliTheme.accent,
                foregroundColor: KeliTheme.bg,
                onPressed: _openActions,
                child: Icon(Icons.add, size: 24),
              ),
            ),
      body: Stack(
        children: [
          // Solid black behind the Unity face — clean black frame around the square, seamless with
          // Unity's own black clear colour (the face floats on black).
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
          // CENTERPIECE: the pinned dynamic view (face / cam / map). Yields the centre to a tool popup.
          if (!overlayUp) _pinnedCenter(views, conn),
          // FLOATING dynamic views (face / cam / map) as draggable windows — each with pin + close.
          ..._floatingViews(views, faceAt),
          // What Maradel currently sees + where she thinks she is (perception loop), top-right.
          const PerceptionWindow(),
          // Listening / thinking indicator (top-centre) — driven by Maradel's ears state (voice:attention).
          const _AttentionIndicator(),
          // Read-only Maradel chat mirror — draggable floating window, top-right; toggled from the AppBar.
          if (_showChat && !overlayUp) const MaradelChatWindow(),
          // SHOWN windows (push: show_text / show_image / show_diary) — FULL-SCREEN and ON TOP of all the
          // ambient windows (face / floating cam-map / perception / chat). Newest on top; closing it
          // (its ✕, or the AppBar "Close all") reveals the next.
          if (conn.commands.isNotEmpty)
            Positioned.fill(
              child: buildCommandView(
                context,
                conn.commands.last,
                () => conn.dismiss(conn.commands.last.id),
              ),
            ),
          // Interactive request from Maradel — one at a time over a scrim.
          if (conn.activeRequest != null)
            _RequestOverlay(
              key: ValueKey(conn.activeRequest!.id),
              command: conn.activeRequest!,
              onComplete: ({required ok, data, reason}) =>
                  conn.completeRequest(conn.activeRequest!.id, ok: ok, data: data, reason: reason),
            ),
          // User-launched action (FAB) being composed → same views, result goes to Maradel.
          if (_selfAction != null)
            _RequestOverlay(
              key: ValueKey('self-${_selfAction!.event}'),
              command: _selfAction!,
              onComplete: _completeSelf,
            ),
          // Tool popup up → keep the face visible as a small TOP-RIGHT overlay (unless it's closed).
          // Same single Unity view, reparented here via its GlobalKey (no reload).
          if (faceAt == _FacePlace.corner)
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox.square(
                      dimension: (MediaQuery.of(context).size.shortestSide * 0.3).clamp(120.0, 240.0),
                      child: _face,
                    ),
                  ),
                ),
              ),
            ),
          // Face "closed" (parked in the dashboard) → keep Unity mounted off-screen so it stays warm
          // (the Unity engine is a process-wide singleton; this just keeps the texture attached).
          if (faceAt == _FacePlace.offstage) Offstage(child: _face),
          // Live "ears" status bar (voice meter + connection + chunks + expandable log).
          const Align(alignment: Alignment.bottomCenter, child: MicStatusBar()),
        ],
      ),
    );
  }
}

/// Where the single warm Unity face is mounted this frame (see [_HomeScreenState.build]).
enum _FacePlace { center, floating, corner, offstage }

/// Pinned centerpiece presentation for a non-face view (cam / map): a titled frame, centered like the
/// face, with quick **float** / **close** actions in its little header.
class _PinnedView extends StatelessWidget {
  const _PinnedView({required this.id, required this.child, required this.onFloat, required this.onClose});
  final String id;
  final Widget child;
  final VoidCallback onFloat;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: LayoutBuilder(
          builder: (context, c) {
            final side = (c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight) * 0.9;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: side,
                  child: Row(
                    children: [
                      Icon(ViewIds.icon(id), size: 18, color: KeliTheme.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(ViewIds.title(id),
                            style: TextStyle(color: KeliTheme.text, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      ),
                      IconButton(
                        tooltip: 'Float',
                        icon: Icon(Icons.picture_in_picture_alt, color: KeliTheme.accentDim, size: 20),
                        onPressed: onFloat,
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: Icon(Icons.close, color: KeliTheme.accentDim, size: 20),
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(width: side, height: side, child: child),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Shown in the centre when nothing is pinned — points the user at the Widgets dashboard.
class _EmptyCenter extends StatelessWidget {
  const _EmptyCenter();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dashboard_customize_outlined, size: 48, color: KeliTheme.muted),
          const SizedBox(height: 12),
          Text('Nothing pinned', style: TextStyle(color: KeliTheme.text, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Open Widgets (top bar) to pin a view here.',
              style: TextStyle(color: KeliTheme.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Full-screen scrim hosting the active interactive request's view.
class _RequestOverlay extends StatelessWidget {
  const _RequestOverlay({super.key, required this.command, required this.onComplete});

  final IncomingCommand command;
  final RequestComplete onComplete;

  @override
  Widget build(BuildContext context) {
    // Front flashlight: the screen IS the light → render edge-to-edge white, no scrim / width cap.
    if (command.event == 'front_flashlight') {
      return Positioned.fill(child: buildRequestView(context, command, onComplete));
    }
    final h = MediaQuery.of(context).size.height;
    return Container(
      color: Colors.black87,
      child: SafeArea(
        // Center + cap width (landscape-friendly), and allow the view to scroll if it's taller
        // than the (short) landscape height instead of overflowing.
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 600, maxHeight: h),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(12),
              child: buildRequestView(context, command, onComplete),
            ),
          ),
        ),
      ),
    );
  }
}

/// The persistent centerpiece of the main page: Maradel's embedded 3D Unity face, always on and
/// rendered as a centered SQUARE. Unity is a single resident instance — it stays warm for the app's
/// lifetime because [HomeScreen] is the one screen and is never disposed. Unity itself connects to
/// Maradel (:9100) over Socket.IO and fetches the voice WAVs over HTTP, so the face talks + lipsyncs
/// with no Flutter-side bridge. A small status line under the square keeps the Keli link visible.
class _FaceStage extends StatelessWidget {
  const _FaceStage({required this.conn, required this.face});
  final KeliConnection conn;
  final Widget face; // the single shared EmbedUnity (see _HomeScreenState._face)

  @override
  Widget build(BuildContext context) {
    final ok = conn.connected;
    final color = ok ? KeliTheme.accent : KeliTheme.danger;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, c) {
          // Largest square that fits, leaving room for the status line.
          final side = (c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight) * 0.92;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Face square flanked by the big ◀/▶ avatar switchers (overlaid on the side edges).
                SizedBox(
                  width: side,
                  height: side,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // No glow/halo around the face — clean black, per request (the teal-green glow
                      // read as a "green overlay" around the Unity widget).
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(width: side, height: side, child: face),
                      ),
                      // Loading overlay while a skin swap is in flight (cleared when Unity echoes the
                      // live avatar) — so ◀/▶ + the picker give immediate feedback instead of feeling dead.
                      Consumer<UnityBridge>(
                        builder: (_, b, _) => b.loading
                            ? Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: ColoredBox(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        CircularProgressIndicator(color: KeliTheme.accent),
                                        const SizedBox(height: 12),
                                        Text('Loading avatar…',
                                            style: TextStyle(color: KeliTheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      Positioned(left: 6, child: _AvatarNavButton(icon: Icons.chevron_left, onTap: () => context.read<UnityBridge>().prevSkin())),
                      Positioned(right: 6, child: _AvatarNavButton(icon: Icons.chevron_right, onTap: () => context.read<UnityBridge>().nextSkin())),
                    ],
                  ),
                ),
                SizedBox(height: 10),
                // Current avatar name + category (Flutter-owned index; Unity stays in sync).
                Consumer<UnityBridge>(
                  builder: (_, bridge, _) {
                    final a = bridge.currentSkin;
                    if (a == null) {
                      return Text('loading avatar…',
                          style: TextStyle(color: KeliTheme.muted, fontSize: 13, fontWeight: FontWeight.w600));
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          a.display,
                          style: TextStyle(color: KeliTheme.text, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                        ),
                        SizedBox(height: 2),
                        Text(
                          bridge.total > 0
                              ? '${a.category.isEmpty ? "—" : a.category} · ${bridge.index + 1}/${bridge.total}'
                              : (a.category.isEmpty ? '' : a.category),
                          style: TextStyle(color: KeliTheme.muted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                        ),
                      ],
                    );
                  },
                ),
                SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(ok ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, size: 16, color: color),
                    SizedBox(width: 6),
                    Text(
                      ok ? 'Maradel · connected' : 'connecting…',
                      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A big, glowing circular ◀/▶ button used to step the face's avatar (sized for a wall tablet).
class _AvatarNavButton extends StatelessWidget {
  const _AvatarNavButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: CircleBorder(),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KeliTheme.bg.withValues(alpha: 0.55),
            border: Border.all(color: KeliTheme.accent.withValues(alpha: 0.6), width: 2),
            boxShadow: KeliTheme.glow(blur: 10, alpha: 0.3),
          ),
          child: Icon(icon, color: KeliTheme.accent, size: 40),
        ),
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  Future<void> _reportBug(BuildContext context, KeliConnection conn) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KeliTheme.surface,
        title: Text('Report a bug', style: TextStyle(color: KeliTheme.accent)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          style: TextStyle(color: KeliTheme.text),
          decoration: InputDecoration(hintText: 'What went wrong?', hintStyle: TextStyle(color: KeliTheme.muted)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: KeliTheme.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text('Send', style: TextStyle(color: KeliTheme.accent))),
        ],
      ),
    );
    if (reason == null || reason.trim().isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('Capturing bug report…')));
    final ok = await conn.reportBug(reason.trim());
    messenger.showSnackBar(SnackBar(content: Text(ok ? '🐞 Bug report saved' : 'Could not save report')));
  }

  Future<void> _requestFeature(BuildContext context, KeliConnection conn) async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KeliTheme.surface,
        title: Text('Request a feature', style: TextStyle(color: KeliTheme.accent)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          style: TextStyle(color: KeliTheme.text),
          decoration: InputDecoration(hintText: 'What should it do?', hintStyle: TextStyle(color: KeliTheme.muted)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: KeliTheme.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text('Send', style: TextStyle(color: KeliTheme.accent))),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    final ok = await conn.requestFeature(text.trim());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '💡 Sent to Maradel' : 'Could not send')));
    }
  }

  Future<void> _editDeviceId(BuildContext context, KeliConnection conn) async {
    final ctrl = TextEditingController(text: conn.deviceId);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KeliTheme.surface,
        title: Text('Device name', style: TextStyle(color: KeliTheme.accent)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: KeliTheme.text),
          decoration: InputDecoration(hintText: 'e.g. roomba-phone', hintStyle: TextStyle(color: KeliTheme.muted)),
          onSubmitted: (s) => Navigator.pop(ctx, s),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: KeliTheme.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text('Save', style: TextStyle(color: KeliTheme.accent))),
        ],
      ),
    );
    if (v != null) await conn.setDeviceId(v);
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<KeliConnection>();
    final mic = context.watch<MicStreamer>();
    final settings = context.watch<KeliSettings>();
    return Drawer(
      backgroundColor: KeliTheme.surface,
      child: SafeArea(
        // Vertically scrollable so the update button + version at the bottom stay reachable on the
        // short landscape wall-tablet (panel content is taller than the screen). The min-height +
        // IntrinsicHeight keeps the Spacer pinning the version to the bottom when there IS room.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text('Keli', style: TextStyle(color: KeliTheme.accent, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text("Maradel's window on this phone", style: TextStyle(color: KeliTheme.muted, fontSize: 12)),
            ),
            Divider(color: KeliTheme.surface2),
            ListTile(
              leading: Icon(conn.connected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  color: conn.connected ? KeliTheme.accent : KeliTheme.danger),
              title: Text(conn.connected ? 'Connected' : 'Disconnected', style: TextStyle(color: KeliTheme.text, fontSize: 14)),
              subtitle: Text(conn.url, style: TextStyle(color: KeliTheme.muted, fontSize: 11)),
            ),
            Divider(color: KeliTheme.surface2),
            // "Ears": stream the tablet mic to Maradel so you can talk to the robot.
            SwitchListTile(
              activeThumbColor: KeliTheme.accent,
              secondary: Icon(mic.enabled ? Icons.mic : Icons.mic_off,
                  color: mic.enabled ? KeliTheme.accent : KeliTheme.muted),
              title: Text('Ears (mic → Maradel)', style: TextStyle(color: KeliTheme.text, fontSize: 14)),
              subtitle: Text(
                mic.enabled
                    ? (mic.connected ? 'streaming → ${mic.target}' : mic.detail)
                    : "off — the robot can't hear you",
                style: TextStyle(color: KeliTheme.muted, fontSize: 11),
              ),
              value: mic.enabled,
              onChanged: (v) => context.read<MicStreamer>().setEnabled(v),
            ),
            Divider(color: KeliTheme.surface2),
            ListTile(
              leading: Icon(Icons.face_retouching_natural_outlined, color: KeliTheme.accent),
              title: Text('Face (preview)', style: TextStyle(color: KeliTheme.text, fontSize: 14)),
              subtitle: Text('the 3D talking face — bridge live, Unity pending',
                  style: TextStyle(color: KeliTheme.muted, fontSize: 11)),
              trailing: Icon(Icons.chevron_right, color: KeliTheme.muted),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => FaceScreen()));
              },
            ),
            Divider(color: KeliTheme.surface2),
            ListTile(
              leading: Icon(Icons.report_problem_outlined, color: KeliTheme.danger),
              title: Text('Report a bug', style: TextStyle(color: KeliTheme.text, fontSize: 14)),
              subtitle: Text('captures app logs + sends to Maradel', style: TextStyle(color: KeliTheme.muted, fontSize: 11)),
              onTap: () {
                Navigator.of(context).pop();
                _reportBug(context, conn);
              },
            ),
            Divider(color: KeliTheme.surface2),
            ListTile(
              leading: Icon(Icons.upload_file, color: KeliTheme.accent),
              title: Text('Upload logs', style: TextStyle(color: KeliTheme.text, fontSize: 14)),
              subtitle: Text('send this session log to the share (keli/logs/)', style: TextStyle(color: KeliTheme.muted, fontSize: 11)),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final settings = context.read<KeliSettings>();
                Navigator.of(context).pop();
                messenger.showSnackBar(SnackBar(content: Text('Uploading logs…')));
                final err = await settings.uploadLogsToShare();
                messenger.showSnackBar(SnackBar(content: Text(err ?? 'Logs uploaded to share (keli/logs/)')));
              },
            ),
            Divider(color: KeliTheme.surface2),
            ListTile(
              leading: Icon(Icons.lightbulb_outline, color: KeliTheme.accent),
              title: Text('Request a feature', style: TextStyle(color: KeliTheme.text, fontSize: 14)),
              subtitle: Text('a wish → Maradel', style: TextStyle(color: KeliTheme.muted, fontSize: 11)),
              onTap: () {
                Navigator.of(context).pop();
                _requestFeature(context, conn);
              },
            ),
            Divider(color: KeliTheme.surface2),
            ListTile(
              leading: Icon(Icons.badge_outlined, color: KeliTheme.accent),
              title: Text('Device name', style: TextStyle(color: KeliTheme.text, fontSize: 14)),
              subtitle: Text(conn.deviceId, style: TextStyle(color: KeliTheme.muted, fontSize: 11)),
              trailing: Icon(Icons.edit, color: KeliTheme.muted, size: 18),
              onTap: () => _editDeviceId(context, conn),
            ),
            Divider(color: KeliTheme.surface2),
            ListTile(
              leading: Icon(Icons.app_registration, color: KeliTheme.accent),
              title: Text('Registration', style: TextStyle(color: KeliTheme.text, fontSize: 14)),
              subtitle: Text(
                settings.registered
                    ? '${settings.instanceName.isEmpty ? "registered" : settings.instanceName} · vol ${(settings.volume * 100).round()}%'
                    : 'not registered — tap to set up',
                style: TextStyle(color: KeliTheme.muted, fontSize: 11),
              ),
              trailing: Icon(Icons.chevron_right, color: KeliTheme.muted),
              onTap: () {
                Navigator.of(context).pop();
                showRegistrationDialog(context, dismissible: true);
              },
            ),
            Divider(color: KeliTheme.surface2),
            ListTile(
              leading: Icon(Icons.alarm, color: KeliTheme.accent),
              title: Text('Reminders', style: TextStyle(color: KeliTheme.text, fontSize: 14)),
              subtitle: Text('what Maradel will remind you of', style: TextStyle(color: KeliTheme.muted, fontSize: 11)),
              trailing: Icon(Icons.chevron_right, color: KeliTheme.muted),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => RemindersPage()));
              },
            ),
            Divider(color: KeliTheme.surface2),
            ListTile(
              leading: Icon(Icons.collections_outlined, color: KeliTheme.accent),
              title: Text('Gallery', style: TextStyle(color: KeliTheme.text, fontSize: 14)),
              subtitle: Text('drawings Maradel showed here', style: TextStyle(color: KeliTheme.muted, fontSize: 11)),
              trailing: Icon(Icons.chevron_right, color: KeliTheme.muted),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => GalleryPage()));
              },
            ),
            Divider(color: KeliTheme.surface2),
            ListTile(
              leading: Icon(Icons.history_edu_outlined, color: KeliTheme.accent),
              title: Text('Changelogs', style: TextStyle(color: KeliTheme.text, fontSize: 14)),
              subtitle: Text("what changed each build", style: TextStyle(color: KeliTheme.muted, fontSize: 11)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChangelogsPage()));
              },
            ),
            Divider(color: KeliTheme.surface2),
            Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 4),
              child: Text('VERSION', style: TextStyle(color: KeliTheme.muted, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
            ),
            UpdateButton(),
            Spacer(),
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('v$kAppVersion (build $kAppBuild)', style: TextStyle(color: KeliTheme.muted, fontSize: 11)),
            ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-centre pill that shows Maradel's ears state: a pulsing mic while she's HEARING you (wake /
/// speech onset) and a spinner while she's THINKING (generating the reply). Driven by `voice:attention`
/// (VoicePlayer). Hidden when idle. Sits just above the bottom MicStatusBar.
class _AttentionIndicator extends StatefulWidget {
  const _AttentionIndicator();

  @override
  State<_AttentionIndicator> createState() => _AttentionIndicatorState();
}

class _AttentionIndicatorState extends State<_AttentionIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vp = context.watch<VoicePlayer>();
    final hearing = vp.hearing, thinking = vp.thinking;
    if (!hearing && !thinking) return const SizedBox.shrink();
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.only(bottom: 48), // clear the 40px MicStatusBar at the very bottom
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: KeliTheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: KeliTheme.accent.withValues(alpha: 0.6)),
              boxShadow: KeliTheme.glow(blur: 14, alpha: 0.35),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (thinking)
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KeliTheme.accent))
                else
                  FadeTransition(
                    opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
                    child: Icon(Icons.mic, size: 18, color: KeliTheme.accent),
                  ),
                const SizedBox(width: 9),
                Text(
                  thinking ? 'Thinking…' : 'Listening…',
                  style: TextStyle(color: KeliTheme.accentBright, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
