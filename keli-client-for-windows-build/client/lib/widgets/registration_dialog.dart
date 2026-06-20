import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/keli_settings.dart';
import '../theme.dart';

/// First-launch (and "switch device") registration popup: name, description, login, password ->
/// POST /keli/register. Keyboard-safe (scrolls so the button is always reachable), dismissible, and
/// focuses + clears the offending field on error. Re-using the same login + password on another tablet
/// moves the instance to it (device-swap).
Future<void> showRegistrationDialog(BuildContext context, {bool dismissible = true}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: dismissible,
    builder: (_) => const _RegistrationDialog(),
  );
}

class _RegistrationDialog extends StatefulWidget {
  const _RegistrationDialog();

  @override
  State<_RegistrationDialog> createState() => _RegistrationDialogState();
}

class _RegistrationDialogState extends State<_RegistrationDialog> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _login;
  final _pass = TextEditingController();
  final _fnName = FocusNode();
  final _fnDesc = FocusNode();
  final _fnLogin = FocusNode();
  final _fnPass = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = context.read<KeliSettings>();
    _name = TextEditingController(text: s.instanceName);
    _desc = TextEditingController(text: s.instanceDesc);
    _login = TextEditingController(text: s.login);
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _login.dispose();
    _pass.dispose();
    _fnName.dispose();
    _fnDesc.dispose();
    _fnLogin.dispose();
    _fnPass.dispose();
    super.dispose();
  }

  // Show an error, focus the offending field, and (for a bad password) clear it.
  void _fail(String msg, FocusNode focus, {TextEditingController? clear}) {
    clear?.clear();
    setState(() {
      _busy = false;
      _error = msg;
    });
    FocusScope.of(context).requestFocus(focus);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_name.text.trim().isEmpty) return _fail('Name is required', _fnName);
    if (_login.text.trim().isEmpty) return _fail('Login is required', _fnLogin);
    if (_pass.text.isEmpty) return _fail('Password is required', _fnPass);

    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<KeliSettings>().register(
          name: _name.text,
          description: _desc.text,
          login: _login.text,
          password: _pass.text,
        );
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
      return;
    }
    // wrong password → clear + focus password; otherwise just surface + focus name
    if (err.toLowerCase().contains('password')) {
      _fail(err, _fnPass, clear: _pass);
    } else {
      _fail(err, _fnName);
    }
  }

  Widget _field(
    TextEditingController c,
    FocusNode fn,
    String label, {
    bool obscure = false,
    TextInputAction action = TextInputAction.next,
    FocusNode? next,
    bool submit = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          focusNode: fn,
          obscureText: obscure,
          maxLines: 1, // all fields single-line
          enabled: !_busy,
          textInputAction: action,
          onSubmitted: (_) {
            if (submit) {
              _submit();
            } else if (next != null) {
              FocusScope.of(context).requestFocus(next);
            }
          },
          style: const TextStyle(color: KeliTheme.text),
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            labelStyle: const TextStyle(color: KeliTheme.muted),
            enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: KeliTheme.surface2)),
            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: KeliTheme.accent)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Keyboard-safe: a centered card whose content scrolls, with bottom padding == keyboard inset so
    // the Register button is always reachable (was getting hidden under the keyboard).
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Dialog(
      backgroundColor: KeliTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + insets),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Register this Keli',
                  style: TextStyle(color: KeliTheme.accent, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              const Text(
                'Name this device and set a login + password. Use the same login & password on another '
                'tablet to move this instance to it.',
                style: TextStyle(color: KeliTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              _field(_name, _fnName, 'Name (e.g. Living room tablet)', next: _fnDesc),
              _field(_desc, _fnDesc, 'Description', next: _fnLogin),
              _field(_login, _fnLogin, 'Login', next: _fnPass),
              _field(_pass, _fnPass, 'Password', obscure: true, action: TextInputAction.done, submit: true),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: Text(_error!, style: const TextStyle(color: KeliTheme.danger, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Close', style: TextStyle(color: KeliTheme.muted)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(backgroundColor: KeliTheme.accent, foregroundColor: KeliTheme.bg),
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Register'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
