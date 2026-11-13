import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _server = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  bool _showServer = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    AppConfig.loadApiBase().then((v) {
      if (mounted) setState(() => _server.text = v);
    });
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(server: _server.text, identifier: _user.text, password: _pass.text);
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -1.1), radius: 1.3, colors: [Color(0xFF2A1250), DColors.background]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AutofillGroup(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [BoxShadow(color: DColors.primary.withValues(alpha: 0.35), blurRadius: 60)],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Image.asset('assets/icon/app_icon.png', width: 112, height: 112, semanticLabel: 'Demonify'),
                            ),
                          ),
                        ),
                        const SizedBox(height: DSpacing.xl),
                        Text('Demonify', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall),
                        const SizedBox(height: DSpacing.xs),
                        Text(s.loginSubtitle, textAlign: TextAlign.center, style: const TextStyle(color: DColors.textMuted)),
                        const SizedBox(height: DSpacing.xxl),
                        TextFormField(
                          controller: _user,
                          decoration: InputDecoration(labelText: s.loginIdentifier, prefixIcon: const Icon(Icons.person_rounded)),
                          autofillHints: const [AutofillHints.username, AutofillHints.email],
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          validator: (v) => (v == null || v.trim().isEmpty) ? s.fieldRequired : null,
                        ),
                        const SizedBox(height: DSpacing.m),
                        TextFormField(
                          controller: _pass,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: s.password,
                            prefixIcon: const Icon(Icons.lock_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscure ? s.showPassword : s.hidePassword,
                              icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) => (v == null || v.isEmpty) ? s.fieldRequired : null,
                        ),
                        const SizedBox(height: DSpacing.m),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 200),
                          crossFadeState: _showServer ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                          firstChild: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => setState(() => _showServer = true),
                              icon: const Icon(Icons.dns_rounded, size: 18),
                              label: Text(s.loginChangeServer),
                            ),
                          ),
                          secondChild: TextFormField(
                            controller: _server,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            decoration: InputDecoration(labelText: s.serverAddress, helperText: s.serverAddressHint, prefixIcon: const Icon(Icons.dns_rounded)),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: DSpacing.m),
                          Container(
                            padding: const EdgeInsets.all(DSpacing.m),
                            decoration: BoxDecoration(color: DColors.danger.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(DRadius.m)),
                            child: Text(_error!, style: const TextStyle(color: Color(0xFFFFC2CD))),
                          ),
                        ],
                        const SizedBox(height: DSpacing.xl),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : Text(s.login),
                        ),
                        const SizedBox(height: DSpacing.m),
                        TextButton(onPressed: () => _showForgot(context), child: Text(s.forgotPassword)),
                        TextButton(onPressed: () => _showInvite(context), child: Text(s.inviteRedeem)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showForgot(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (ctx) => _ForgotSheet(server: _server.text, initial: _user.text.trim()),
      );

  Future<void> _showInvite(BuildContext context) async {
    final email = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _InviteSheet(server: _server.text),
    );
    if (email != null && context.mounted) {
      final s = context.s;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(email.isEmpty ? s.inviteSuccess : '${s.inviteSuccess} ${s.emailLinkSent(email)}'),
      ));
    }
  }
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.server});
  final String server;
  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _code = TextEditingController();
  final _user = TextEditingController();
  final _display = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DSpacing.xl),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.inviteRedeem, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: DSpacing.l),
              TextFormField(controller: _code, decoration: InputDecoration(labelText: s.inviteCode), validator: (v) => (v ?? '').trim().length < 10 ? s.fieldRequired : null),
              const SizedBox(height: DSpacing.m),
              TextFormField(controller: _user, decoration: InputDecoration(labelText: s.username), autocorrect: false, validator: (v) => (v ?? '').trim().length < 3 ? s.usernameRules : null),
              const SizedBox(height: DSpacing.m),
              TextFormField(
                controller: _display,
                decoration: InputDecoration(labelText: s.displayName, helperText: s.displayNameHelp),
                validator: (v) => (v ?? '').trim().isEmpty ? s.fieldRequired : null,
              ),
              const SizedBox(height: DSpacing.m),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(labelText: s.email, helperText: s.inviteEmailHelp),
                validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((v ?? '').trim()) ? null : s.emailInvalid,
              ),
              const SizedBox(height: DSpacing.m),
              TextFormField(controller: _pass, obscureText: true, decoration: InputDecoration(labelText: s.password), validator: (v) => (v ?? '').length < 10 ? s.passwordTooShort : null),
              const SizedBox(height: DSpacing.m),
              TextFormField(controller: _pass2, obscureText: true, decoration: InputDecoration(labelText: s.passwordRepeat), validator: (v) => v != _pass.text ? s.passwordMismatch : null),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: DSpacing.m), child: Text(_error!, style: const TextStyle(color: DColors.danger))),
              const SizedBox(height: DSpacing.l),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (!_form.currentState!.validate()) return;
                        setState(() {
                          _busy = true;
                          _error = null;
                        });
                        // Code kann auch als kompletter Link eingefügt werden
                        final code = _code.text.trim().split('/').last;
                        try {
                          final sent = await ApiClient.redeemInvite(
                            apiBase: AppConfig.normalizeApiBase(widget.server),
                            code: code,
                            username: _user.text.trim(),
                            password: _pass.text,
                            displayName: _display.text.trim(),
                            email: _email.text.trim(),
                          );
                          if (context.mounted) Navigator.of(context).pop(sent ? _email.text.trim() : '');
                        } catch (e) {
                          setState(() => _error = errorText(e));
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: Text(s.inviteSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// „Passwort vergessen“: Anmeldename oder E-Mail → neutraler Hinweis, Link kommt per Mail
class _ForgotSheet extends StatefulWidget {
  const _ForgotSheet({required this.server, required this.initial});
  final String server;
  final String initial;
  @override
  State<_ForgotSheet> createState() => _ForgotSheetState();
}

class _ForgotSheetState extends State<_ForgotSheet> {
  late final _id = TextEditingController(text: widget.initial);
  bool _busy = false;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_id.text.trim().isEmpty) {
      setState(() => _error = context.s.fieldRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final msg = await ApiClient.forgotPassword(apiBase: AppConfig.normalizeApiBase(widget.server), identifier: _id.text.trim());
      if (mounted) setState(() => _message = msg);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.forgotPassword, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: DSpacing.s),
            if (_message != null) ...[
              Text(_message!),
              const SizedBox(height: DSpacing.l),
              Text(s.forgotFallback, style: const TextStyle(color: DColors.textMuted)),
              const SizedBox(height: DSpacing.l),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.backToLogin)),
            ] else ...[
              Text(s.forgotIntro, style: const TextStyle(color: DColors.textMuted)),
              const SizedBox(height: DSpacing.l),
              TextField(
                controller: _id,
                autofocus: widget.initial.isEmpty,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(labelText: s.loginIdentifier, errorText: _error, prefixIcon: const Icon(Icons.person_rounded)),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: DSpacing.l),
              FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? s.forgotSending : s.forgotSend)),
            ],
          ],
        ),
      ),
    );
  }
}
