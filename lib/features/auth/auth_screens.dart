import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:game_playtest_tracker/data.dart';
import 'package:game_playtest_tracker/repository_extras.dart';
import 'package:game_playtest_tracker/studio.dart' show InfoCard;
import 'package:game_playtest_tracker/theme.dart';

const _okColor = Color(0xFF2F6B4A); // 5.6:1 on the cream background

// Colours of the login screen's soft background band. Tune these two to taste.
const _bandTop = Color(0xFFF0E2D8);
const _bandBottom = Color(0xFFE9E0D9);

/// Field with a small label that always sits above the text line (like the design).
InputDecoration _dec(String label) => InputDecoration(
  labelText: label,
  floatingLabelBehavior: FloatingLabelBehavior.always,
  labelStyle: const TextStyle(
    color: muted,
    fontSize: 16,
  ), // shows at 75% = 12px
  floatingLabelStyle: const TextStyle(color: muted, fontSize: 16),
  contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 14),
  enabledBorder: const UnderlineInputBorder(
    borderSide: BorderSide(color: line),
  ),
  focusedBorder: const UnderlineInputBorder(
    borderSide: BorderSide(color: ink, width: 2),
  ),
  errorStyle: const TextStyle(color: errorColor),
  errorBorder: const UnderlineInputBorder(
    borderSide: BorderSide(color: errorColor),
  ),
  focusedErrorBorder: const UnderlineInputBorder(
    borderSide: BorderSide(color: errorColor, width: 2),
  ),
);

bool _validEmail(String? v) =>
    v != null && RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

/// Back that always works: pop if there is something to go back to, otherwise go to [fallback].
void _leave(BuildContext context, {String fallback = '/'}) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

// ---------------------------------------------------------------- login hero (glow, orbit ring, logo)

/// Soft peach glow plus a thin orbit ring with a dot, centred in the box.
class _HeroPainter extends CustomPainter {
  const _HeroPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);

    final glow = Rect.fromCenter(
      center: c,
      width: size.width * .95,
      height: size.height * .95,
    );
    canvas.drawOval(
      glow,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x4DEC9A7A), Color(0x00EC9A7A)],
        ).createShader(glow),
    );

    const r = 76.0;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xCCEC9A7A),
    );

    const angle = math.pi - 0.12; // left side, just below the middle
    canvas.drawCircle(
      c + Offset(r * math.cos(angle), r * math.sin(angle)),
      4.5,
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Dark rounded square with three stacked layers (solid top, two outlined below).
class _LayersPainter extends CustomPainter {
  const _LayersPainter();
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * .3)),
      Paint()..color = darkPanel,
    );
    final cx = s.width / 2;
    final w = s.width * .27, h = s.width * .13;

    Path diamond(double cy) => Path()
      ..moveTo(cx, cy - h)
      ..lineTo(cx + w, cy)
      ..lineTo(cx, cy + h)
      ..lineTo(cx - w, cy)
      ..close();
    Path vee(double cy) => Path()
      ..moveTo(cx - w, cy)
      ..lineTo(cx, cy + h)
      ..lineTo(cx + w, cy);

    canvas.drawPath(diamond(s.height * .34), Paint()..color = accent);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * .03
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      vee(s.height * .50),
      stroke..color = const Color(0xFFB9ADA4),
    );
    canvas.drawPath(
      vee(s.height * .64),
      stroke..color = const Color(0xFF8A7E76),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LoginHero extends StatelessWidget {
  const _LoginHero();
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Playtest Tracker logo',
    excludeSemantics: true,
    child: const SizedBox(
      height: 250,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: CustomPaint(painter: _HeroPainter())),
          SizedBox(
            width: 72,
            height: 72,
            child: CustomPaint(painter: _LayersPainter()),
          ),
        ],
      ),
    ),
  );
}

/// Message with an icon and a colour (never colour alone). Read aloud when it appears.
class _Notice extends StatelessWidget {
  final String text;
  final bool error;
  const _Notice(this.text, {this.error = false});
  @override
  Widget build(BuildContext context) {
    final color = error ? errorColor : _okColor;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Password field with a show / hide button (48dp tap target).
class _PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? helper;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  const _PasswordField({
    required this.controller,
    required this.label,
    this.helper,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.validator,
  });
  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hidden = true;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: _hidden,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: widget.autofillHints,
    textInputAction: widget.textInputAction,
    onFieldSubmitted: widget.onSubmitted,
    validator: widget.validator,
    decoration: _dec(widget.label).copyWith(
      helperText: widget.helper,
      helperStyle: const TextStyle(color: muted),
      suffixIcon: IconButton(
        tooltip: _hidden ? 'Show password' : 'Hide password',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(
          _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: muted,
        ),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    ),
  );
}

// ---------------------------------------------------------------- login / sign up

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false, _busy = false;
  String? _error, _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return; // the keyboard's Done key could fire this twice
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final repo = ref.read(repoProvider);
      if (_signUp) {
        final signedIn = await repo.signUp(_email.text.trim(), _password.text);
        if (!signedIn) {
          _info = 'Account created. Open the link we emailed you, then log in.';
          _signUp = false;
          _password.clear();
        }
      } else {
        await repo.signIn(_email.text.trim(), _password.text);
      }
    } catch (e) {
      _error = friendlyError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Switch between Log in and Create account: keep the email, clear the password and every old message.
  void _toggleMode() {
    final email = _email.text;
    _form.currentState?.reset();
    _email.text = email;
    _password.clear();
    setState(() {
      _signUp = !_signUp;
      _error = null;
      _info = null;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, .22, .34, .60, .90],
          colors: [bg, bg, _bandTop, _bandBottom, bg],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const _LoginHero(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: AutofillGroup(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            _signUp ? 'Create account' : 'Welcome back',
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w400,
                              letterSpacing: -0.9,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _signUp
                              ? 'Sign up with your email to start tracking playtests.'
                              : 'Log in to review your playtest reports.',
                          style: const TextStyle(color: muted, fontSize: 13.5),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.next,
                          decoration: _dec('Email'),
                          validator: (v) => _validEmail(v)
                              ? null
                              : 'Enter a valid email address.',
                        ),
                        const SizedBox(height: 8),
                        _PasswordField(
                          controller: _password,
                          label: 'Password',
                          helper: _signUp ? 'At least 6 characters' : null,
                          autofillHints: [
                            _signUp
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          validator: (v) => (v == null || v.length < 6)
                              ? 'Use at least 6 characters.'
                              : null,
                        ),
                        if (!_signUp)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => context.push('/forgot-password'),
                              child: const Text(
                                'Forgot password?',
                                style: TextStyle(color: muted, fontSize: 14),
                              ),
                            ),
                          ),
                        if (_error != null) _Notice(_error!, error: true),
                        if (_info != null) _Notice(_info!),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: Text(
                            _busy
                                ? 'Please wait...'
                                : (_signUp ? 'Create account' : 'Log in'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: TextButton(
                            onPressed: _busy ? null : _toggleMode,
                            child: Text.rich(
                              TextSpan(
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 14,
                                ),
                                children: [
                                  TextSpan(
                                    text: _signUp
                                        ? 'Have an account? '
                                        : 'New here? ',
                                  ),
                                  TextSpan(
                                    text: _signUp
                                        ? 'Log in'
                                        : 'Create an account',
                                    style: const TextStyle(
                                      color: ink,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- forgot password

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotState();
}

class _ForgotState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  String? _error, _sentTo;
  bool _busy = false;
  int _wait = 0; // seconds before another link may be requested
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    _wait = 30;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _wait--;
        if (_wait <= 0) t.cancel();
      });
    });
  }

  Future<void> _send() async {
    if (_busy || _wait > 0) return;
    if (!_validEmail(_email.text)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repoProvider).sendPasswordReset(_email.text.trim());
      _sentTo = _email.text.trim();
      _startCooldown();
    } catch (e) {
      _error = friendlyError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          TopBar(
            'Reset password',
            onBack: () => _leave(context, fallback: '/login'),
          ),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
              children: [
                const BigTitle(
                  'Forgot your password?',
                  sub: 'We will email you a link that opens this app.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _send(),
                  decoration: _dec('Email'),
                ),
                if (_error != null) _Notice(_error!, error: true),
                if (_sentTo != null)
                  _Notice(
                    'If an account exists for $_sentTo, a reset link is on its way. Open it on this phone.',
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: (_busy || _wait > 0) ? null : _send,
                  child: Text(
                    _busy
                        ? 'Sending...'
                        : _wait > 0
                        ? 'Send again in ${_wait}s'
                        : (_sentTo != null ? 'Send again' : 'Send reset link'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------- set a new password
// Two ways in: (1) Profile > Password > Change (a pushed screen, so it can go back), or
// (2) the reset link in an email (the router replaces everything, so there is nothing to go back to).

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetState();
}

class _ResetState extends ConsumerState<ResetPasswordScreen> {
  final _pw = TextEditingController(), _pw2 = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_pw.text.length < 6) {
      return setState(() => _error = 'Use at least 6 characters.');
    }
    if (_pw.text != _pw2.text) {
      return setState(() => _error = 'The two passwords do not match.');
    }
    FocusScope.of(context).unfocus();
    final changing = context.canPop();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repoProvider).setPassword(_pw.text);
      if (!mounted) return;
      if (changing) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Password updated')),
        );
        context.pop(); // back to Profile
      } else {
        // Reset-link flow: finish by signing out so the app leaves its "recovery" state cleanly.
        await sb.auth.signOut();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Password updated. Log in with your new password.'),
          ),
        );
      }
      return;
    } catch (e) {
      _error = friendlyError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final changing = context.canPop();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (changing)
              TopBar('Change password', onBack: () => _leave(context))
            else
              const SizedBox(height: 40),
            Expanded(
              child: AutofillGroup(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  children: [
                    BigTitle(
                      changing
                          ? 'Change your password'
                          : 'Choose a new password',
                      sub: changing ? 'Pick a new password for your account.' : 'You opened the reset link from your email. Choose a new password to finish.',
                    ),
                    const SizedBox(height: 12),
                    _PasswordField(
                      controller: _pw,
                      label: 'New password',
                      helper: 'At least 6 characters',
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 8),
                    _PasswordField(
                      controller: _pw2,
                      label: 'Repeat new password',
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                    ),
                    if (_error != null) _Notice(_error!, error: true),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(_busy ? 'Saving...' : 'Save password'),
                    ),
                    if (!changing)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Center(
                          child: TextButton(
                            onPressed: _busy ? null : () => sb.auth.signOut(),
                            child: const Text(
                              'Log out instead',
                              style: TextStyle(color: ink),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- delete account

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteState();
}

class _DeleteState extends ConsumerState<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repoProvider).deleteAccount();
      return; // the auth listener sends the router back to the login screen
    } catch (e) {
      _error = friendlyError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _confirm.text.trim().toUpperCase() == 'DELETE';
    return PopScope(
      canPop: !_busy, // no leaving half-way through a deletion
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              TopBar(
                'Delete account',
                onBack: () {
                  if (!_busy) _leave(context);
                },
              ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  children: [
                    const BigTitle(
                      'Delete your account',
                      sub: 'This cannot be undone.',
                    ),
                    const SizedBox(height: 16),
                    const InfoCard(
                      'What gets deleted',
                      'Your account and email, every game you created, and everything under those games: '
                          'builds, sessions, events, reports, retests and event definitions. Nothing is kept. '
                          'You will be signed out when it is done.',
                    ),
                    const SizedBox(height: 16),
                    const Text('Type DELETE to confirm.'),
                    TextField(
                      controller: _confirm,
                      enabled: !_busy,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (ready) _delete();
                      },
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.characters,
                      decoration: _dec('Confirmation'),
                    ),
                    if (_error != null) _Notice(_error!, error: true),
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: errorColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: (_busy || !ready) ? null : _delete,
                      child: Text(_busy ? 'Deleting...' : 'Delete my account'),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
