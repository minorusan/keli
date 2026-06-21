import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

enum WindowCorner { topLeft, topRight }

/// A floating, draggable, collapsible window with the fel-frost chrome (glow border + header).
///
/// Anchored to a default corner; the user can drag it anywhere. Position is **not persisted** —
/// it resets to the default corner each app launch. Never fully dismissed, only collapsed to its
/// header. Used for the live Tapo cam + minimap overlays (see [TapoCamWindow] / [TapoMapWindow]).
class DraggableWindow extends StatefulWidget {
  const DraggableWindow({
    super.key,
    required this.title,
    required this.icon,
    required this.corner,
    required this.child,
    this.width = 240,
    this.height = 200,
    this.onPin,
    this.onClose,
  });

  final String title;
  final IconData icon;
  final WindowCorner corner;
  final Widget child;
  final double width;
  final double height;

  /// If set, a "pin" button in the header makes this view the centered centerpiece.
  final VoidCallback? onPin;

  /// If set, a "close" button parks this view (re-openable from the Widgets dashboard).
  final VoidCallback? onClose;

  @override
  State<DraggableWindow> createState() => _DraggableWindowState();
}

class _DraggableWindowState extends State<DraggableWindow> {
  static const double _margin = 12, _headerH = 32;
  Offset? _pos; // null until first layout → defaults to the chosen corner
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final top = media.padding.top + _margin;
    final w = _collapsed ? 140.0 : widget.width;
    final h = _collapsed ? _headerH : widget.height;

    final defaultPos = switch (widget.corner) {
      WindowCorner.topLeft => Offset(_margin, top),
      WindowCorner.topRight => Offset(size.width - widget.width - _margin, top),
    };
    final pos = _pos ?? defaultPos;
    // Keep it on-screen across drags / orientation changes.
    final clamped = Offset(
      pos.dx.clamp(0.0, (size.width - w).clamp(0.0, size.width)),
      pos.dy.clamp(top - _margin, (size.height - h).clamp(0.0, size.height)),
    );

    return Positioned(
      left: clamped.dx,
      top: clamped.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _pos = clamped + d.delta),
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: KeliTheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: KeliTheme.accent.withValues(alpha: 0.6)),
            boxShadow: KeliTheme.glow(blur: 16, alpha: 0.35),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              if (!_collapsed) SizedBox(width: w, height: h - _headerH, child: widget.child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      height: _headerH,
      padding: EdgeInsets.symmetric(horizontal: 10),
      color: KeliTheme.surface2,
      child: Row(
        children: [
          Icon(widget.icon, size: 15, color: KeliTheme.accent),
          SizedBox(width: 6),
          Flexible(
            child: Text(widget.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: KeliTheme.accentBright, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          ),
          const Spacer(),
          if (widget.onPin != null)
            _HeaderBtn(icon: Icons.push_pin_outlined, tip: 'Pin (center)', onTap: widget.onPin!),
          _HeaderBtn(
            icon: _collapsed ? Icons.open_in_full : Icons.close_fullscreen,
            tip: _collapsed ? 'Expand' : 'Collapse',
            onTap: () => setState(() => _collapsed = !_collapsed),
          ),
          if (widget.onClose != null)
            _HeaderBtn(icon: Icons.close, tip: 'Close', onTap: widget.onClose!),
        ],
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  const _HeaderBtn({required this.icon, required this.tip, required this.onTap});
  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(icon, size: 15, color: KeliTheme.accentDim),
        ),
      ),
    );
  }
}

/// A periodically cache-busted network image (for the MJPEG-style cam/map endpoints, which serve a
/// fresh JPEG per request). [interval] sets the refresh cadence.
class RefreshingImage extends StatefulWidget {
  const RefreshingImage({
    super.key,
    required this.urlBuilder,
    required this.interval,
    this.fit = BoxFit.contain,
    this.offline = 'no signal',
  });

  final String Function(int tick) urlBuilder;
  final Duration interval;
  final BoxFit fit;
  final String offline;

  @override
  State<RefreshingImage> createState() => _RefreshingImageState();
}

class _RefreshingImageState extends State<RefreshingImage> {
  int _tick = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() => _tick = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      widget.urlBuilder(_tick),
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Center(
        child: Text(widget.offline, style: TextStyle(color: KeliTheme.muted, fontSize: 12)),
      ),
    );
  }
}
