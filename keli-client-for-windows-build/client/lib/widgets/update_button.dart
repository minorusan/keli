import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/update_service.dart';
import '../theme.dart';

/// Side-panel update control (mirrors Maradel's): on open it polls
/// `/version.json` and, if a newer build is published, offers a one-tap
/// download of the APK; otherwise shows "up to date".
class UpdateButton extends StatefulWidget {
  const UpdateButton({super.key, UpdateService? service}) : _service = service;

  final UpdateService? _service;

  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  late final UpdateService _service = widget._service ?? UpdateService();
  UpdateInfo? _info;
  bool _checking = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final info = await _service.check();
      if (mounted) setState(() { _info = info; _checking = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _checking = false; });
    }
  }

  Future<void> _download() async {
    final info = _info;
    if (info == null) return;
    final ok = await launchUrl(Uri.parse(info.apkUrl), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open the download')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return ListTile(
        leading: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: KeliTheme.accent)),
        title: Text('Checking for updates…', style: TextStyle(color: KeliTheme.muted, fontSize: 13)),
      );
    }
    if (_error != null) {
      return ListTile(
        leading: Icon(Icons.refresh, color: KeliTheme.muted),
        title: Text('Update check failed', style: TextStyle(color: KeliTheme.muted, fontSize: 13)),
        subtitle: Text('tap to retry', style: TextStyle(color: KeliTheme.muted, fontSize: 11)),
        onTap: _check,
      );
    }
    final info = _info!;
    if (info.available) {
      return ListTile(
        leading: Icon(Icons.system_update, color: KeliTheme.accent),
        title: Text('Download update · v${info.version} (build ${info.build})',
            style: TextStyle(color: KeliTheme.accent, fontSize: 13, fontWeight: FontWeight.w600)),
        onTap: _download,
      );
    }
    return ListTile(
      leading: Icon(Icons.check_circle_outline, color: KeliTheme.accentDim),
      title: Text('Up to date · v$kAppVersion (build $kAppBuild)',
          style: TextStyle(color: KeliTheme.muted, fontSize: 13)),
      onTap: _check,
    );
  }
}
