import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import 'auth_controller.dart';

/// Ersteinrichtung nach der Anmeldung:
/// 1. Startpasswort → Anzeigename + eigenes Passwort (vom Server erzwungen)
/// 2. E-Mail-Adresse erfassen und per Link bestätigen (wenn der Server Mailversand hat)
/// Bestehende Konten ohne E-Mail sehen nur Schritt 2.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Zurück aus dem Browser/Mailprogramm → Bestätigung automatisch prüfen
    _lifecycle = AppLifecycleListener(onResume: () {
      final s = ref.read(authProvider).value;
      if (s != null && s.needsEmailSetup && s.setup.pendingEmail != null) {
        ref.read(authProvider.notifier).refreshAccount().catchError((_) {});
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = ref.watch(authProvider).value;
    if (session == null) return const Scaffold();
    final steps = [if (session.user.mustChangePassword || session.needsPasswordSetup) 1, if (session.setup.emailRequired) 2];
    final current = session.needsPasswordSetup ? 1 : 2;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.setupTitle),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(onPressed: () => ref.read(authProvider.notifier).logout(), child: Text(s.logout)),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (steps.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DSpacing.m),
                      child: Text(s.setupStep(steps.indexOf(current) + 1, steps.length), style: const TextStyle(color: DColors.textMuted)),
                    ),
                  if (session.needsPasswordSetup) const _PasswordStep() else const _EmailStep(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordStep extends ConsumerStatefulWidget {
  const _PasswordStep();
  @override
  ConsumerState<_PasswordStep> createState() => _PasswordStepState();
}

class _PasswordStepState extends ConsumerState<_PasswordStep> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: ref.read(currentUserProvider)?.displayName ?? '');
  final _current = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _current, _pw, _pw2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final auth = ref.read(authProvider.notifier);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.completeSetup(
        displayName: _name.text.trim(),
        currentPassword: auth.recentPassword ?? _current.text,
        newPassword: _pw.text,
      );
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final knowsStartPassword = ref.read(authProvider.notifier).recentPassword != null;
    return Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.setupPasswordTitle, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: DSpacing.s),
            Text(s.setupPasswordIntro, style: const TextStyle(color: DColors.textMuted)),
            const SizedBox(height: DSpacing.xl),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: s.displayName, helperText: s.displayNameHelp, prefixIcon: const Icon(Icons.badge_rounded)),
              textInputAction: TextInputAction.next,
              maxLength: 64,
              validator: (v) => (v ?? '').trim().isEmpty ? s.fieldRequired : null,
            ),
            if (!knowsStartPassword) ...[
              const SizedBox(height: DSpacing.m),
              TextFormField(
                controller: _current,
                obscureText: true,
                decoration: InputDecoration(labelText: s.setupStartPassword, prefixIcon: const Icon(Icons.key_rounded)),
                autofillHints: const [AutofillHints.password],
                validator: (v) => (v ?? '').isEmpty ? s.fieldRequired : null,
              ),
            ],
            const SizedBox(height: DSpacing.m),
            TextFormField(
              controller: _pw,
              obscureText: true,
              decoration: InputDecoration(labelText: s.newPassword, prefixIcon: const Icon(Icons.lock_rounded)),
              autofillHints: const [AutofillHints.newPassword],
              validator: (v) => (v ?? '').length < 10 ? s.passwordTooShort : null,
            ),
            const SizedBox(height: DSpacing.m),
            TextFormField(
              controller: _pw2,
              obscureText: true,
              decoration: InputDecoration(labelText: s.passwordRepeat, prefixIcon: const Icon(Icons.lock_rounded)),
              autofillHints: const [AutofillHints.newPassword],
              validator: (v) => v != _pw.text ? s.passwordMismatch : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_error != null) _ErrorText(_error!),
            const SizedBox(height: DSpacing.xl),
            FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const _Spinner() : Text(s.setupContinue)),
          ],
        ),
      ),
    );
  }
}

class _EmailStep extends ConsumerStatefulWidget {
  const _EmailStep();
  @override
  ConsumerState<_EmailStep> createState() => _EmailStepState();
}

class _EmailStepState extends ConsumerState<_EmailStep> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  bool _editing = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(String email) => _run(() async {
        final auth = ref.read(authProvider.notifier);
        await auth.requestEmail(email: email.trim(), password: auth.recentPassword ?? _pw.text);
        if (mounted) setState(() => _editing = false);
      });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = ref.watch(authProvider).value!;
    final pending = session.setup.pendingEmail;
    final needsPassword = ref.read(authProvider.notifier).recentPassword == null;
    final showForm = pending == null || _editing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.setupEmailTitle, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: DSpacing.s),
        Text(s.setupEmailIntro, style: const TextStyle(color: DColors.textMuted)),
        const SizedBox(height: DSpacing.xl),
        if (showForm)
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(labelText: s.email, prefixIcon: const Icon(Icons.alternate_email_rounded)),
                  validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((v ?? '').trim()) ? null : s.emailInvalid,
                ),
                if (needsPassword) ...[
                  const SizedBox(height: DSpacing.m),
                  TextFormField(
                    controller: _pw,
                    obscureText: true,
                    decoration: InputDecoration(labelText: s.passwordConfirmLabel, prefixIcon: const Icon(Icons.lock_rounded)),
                    autofillHints: const [AutofillHints.password],
                    validator: (v) => (v ?? '').isEmpty ? s.fieldRequired : null,
                  ),
                ],
                if (_error != null) _ErrorText(_error!),
                const SizedBox(height: DSpacing.xl),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () {
                          if (_form.currentState?.validate() ?? false) _send(_email.text);
                        },
                  child: _busy ? const _Spinner() : Text(s.emailSendLink),
                ),
                if (pending != null)
                  TextButton(onPressed: _busy ? null : () => setState(() => _editing = false), child: Text(s.cancel)),
              ],
            ),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(DSpacing.l),
            decoration: BoxDecoration(color: DColors.highlight, borderRadius: BorderRadius.circular(DRadius.m)),
            child: Row(
              children: [
                const Icon(Icons.mark_email_unread_rounded, color: DColors.primaryHover),
                const SizedBox(width: DSpacing.m),
                Expanded(child: Text(s.emailLinkSent(pending))),
              ],
            ),
          ),
          if (_info != null) Padding(padding: const EdgeInsets.only(top: DSpacing.m), child: Text(_info!, style: const TextStyle(color: DColors.textMuted))),
          if (_error != null) _ErrorText(_error!),
          const SizedBox(height: DSpacing.xl),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await ref.read(authProvider.notifier).refreshAccount();
                      final now = ref.read(authProvider).value;
                      if (mounted && now != null && now.needsEmailSetup) setState(() => _info = s.emailNotYetConfirmed);
                    }),
            child: _busy ? const _Spinner() : Text(s.emailIConfirmed),
          ),
          const SizedBox(height: DSpacing.s),
          OutlinedButton(
            onPressed: _busy || needsPassword
                ? null
                : () async {
                    await _send(pending);
                    if (mounted && _error == null) setState(() => _info = s.emailLinkResent);
                  },
            child: Text(s.emailResend),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _editing = true;
                      _email.text = pending;
                    }),
            child: Text(needsPassword ? s.emailResendOrChange : s.emailChangeAddress),
          ),
        ],
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: DSpacing.m),
        child: Text(text, style: const TextStyle(color: DColors.danger)),
      );
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white));
}
