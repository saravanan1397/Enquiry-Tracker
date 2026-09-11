import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/email_recovery_service.dart';
import 'services/leadloop_auth_service.dart';

String recoveryMessage(Object error) {
  if (error is FormatException) return error.message;
  if (error is LeadloopAuthException) return error.message;
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'too-many-requests' => 'Too many attempts. Wait and try again.',
      'invalid-credential' ||
      'wrong-password' =>
        'Check your email and current PIN.',
      'email-already-in-use' =>
        'This email belongs to another account. Use your own email.',
      'requires-recent-login' ||
      'user-token-expired' =>
        'Sign in again, then repeat this action.',
      'network-request-failed' =>
        'Internet is required. Check your connection and try again.',
      _ => 'Could not complete the email request. Please try again.',
    };
  }
  return 'Could not complete the request. Check your connection and try again.';
}

class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key, this.sendReset});

  final Future<void> Function(String email)? sendReset;

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class OwnerForgotPasswordScreen extends StatefulWidget {
  const OwnerForgotPasswordScreen({super.key, this.sendReset});

  final Future<void> Function(String email)? sendReset;

  @override
  State<OwnerForgotPasswordScreen> createState() =>
      _OwnerForgotPasswordScreenState();
}

class _OwnerForgotPasswordScreenState extends State<OwnerForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await (widget.sendReset ?? EmailRecoveryService().sendOwnerReset)(
        _email.text.trim(),
      );
      if (mounted) {
        setState(() => _message =
            'If this owner email is registered, a password reset link has been sent. Check the inbox and spam folder.');
      }
    } catch (error) {
      if (mounted) setState(() => _message = recoveryMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reset owner password')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Enter the email address registered to the owner account.',
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration:
                          const InputDecoration(labelText: 'Owner email'),
                      validator: (value) =>
                          RecoveryValidation.email(value ?? '')
                              ? null
                              : 'Enter a valid owner email address.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _send,
                      child: Text(_busy ? 'Sending…' : 'Send reset link'),
                    ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(_message!),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await (widget.sendReset ?? EmailRecoveryService().sendReset)(
        _email.text.trim(),
      );
      if (mounted) {
        setState(() => _message =
            'If this email is registered, a reset link has been sent. Check your inbox and spam folder. Open the link and choose a new numeric PIN.');
      }
    } catch (error) {
      if (mounted) setState(() => _message = recoveryMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reset promoter PIN')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Enter the verified email linked to your promoter account. No old PIN or owner-issued code is needed.',
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Registered recovery email',
                      ),
                      validator: (value) =>
                          RecoveryValidation.email(value ?? '')
                              ? null
                              : 'Enter your real registered email address.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _send,
                      child: Text(_busy ? 'Sending…' : 'Send reset link'),
                    ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(_message!),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'No email linked yet? If you know your current PIN, return to sign-in and choose “Set up / verify recovery email”. If you are locked out, contact the owner.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class RecoveryEmailScreen extends StatefulWidget {
  const RecoveryEmailScreen({super.key});

  @override
  State<RecoveryEmailScreen> createState() => _RecoveryEmailScreenState();
}

class _RecoveryEmailScreenState extends State<RecoveryEmailScreen> {
  final _email = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final email = FirebaseAuth.instance.currentUser?.email;
    if (!RecoveryValidation.legacy(email)) _email.text = email!;
  }

  @override
  void dispose() {
    _email.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _perform({required bool confirm}) async {
    if (!RecoveryValidation.email(_email.text) ||
        !RecoveryValidation.pin(_pin.text)) {
      setState(() => _message =
          'Enter a real email address and your current PIN (6–128 digits).');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final service = EmailRecoveryService();
      if (confirm) {
        final user = await service.confirmVerification(_email.text, _pin.text);
        await LeadloopAuthService().rememberVerifiedEmail(user);
        if (mounted) {
          setState(() => _message =
              'Email verified and remembered on this device. Continue using mobile number + PIN. On a new device, enter this email once.');
        }
      } else {
        await service.sendVerification(_email.text, _pin.text);
        if (mounted) {
          setState(() => _message =
              'Verification link sent. Open it, return here and tap “I verified my email”. Your account and enquiries stay unchanged.');
        }
      }
    } catch (error) {
      if (mounted) setState(() => _message = recoveryMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Recovery email')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Link an email you can access before you forget your PIN. Your account, records and owner approval will not change.',
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Your real recovery email',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pin,
                    enabled: !_busy,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(128),
                    ],
                    decoration: const InputDecoration(labelText: 'Current PIN'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : () => _perform(confirm: false),
                    child: const Text('Send verification email'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _perform(confirm: true),
                    child: const Text('I verified my email'),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(_message!),
                    ),
                  const Text(
                    'On a new device or after clearing app data, enter your email once using “New device / email changed?” on sign-in. No PIN is stored on the device.',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Handles Firebase email-action links on the hosted Flutter web app. This
/// keeps a promoter's password constrained to the app's numeric PIN format.
class EmailActionScreen extends StatefulWidget {
  const EmailActionScreen({
    super.key,
    required this.mode,
    required this.code,
    this.ownerPassword = false,
    this.verifyResetCode,
    this.confirmReset,
    this.applyCode,
  });

  final String mode;
  final String code;
  final bool ownerPassword;
  final Future<String> Function(String code)? verifyResetCode;
  final Future<void> Function(String code, String pin)? confirmReset;
  final Future<void> Function(String code)? applyCode;

  static EmailActionScreen? fromUri(Uri uri) {
    final mode = uri.queryParameters['mode'];
    final code = uri.queryParameters['oobCode'];
    if (mode == null || code == null || code.isEmpty) return null;
    final continueUrl = Uri.tryParse(uri.queryParameters['continueUrl'] ?? '');
    final recovery = uri.queryParameters['recovery'] ??
        continueUrl?.queryParameters['recovery'];
    return EmailActionScreen(
      mode: mode,
      code: code,
      ownerPassword: recovery == 'owner',
    );
  }

  @override
  State<EmailActionScreen> createState() => _EmailActionScreenState();
}

class _EmailActionScreenState extends State<EmailActionScreen> {
  final _pin = TextEditingController();
  final _confirmPin = TextEditingController();
  bool _busy = true;
  bool _ready = false;
  bool _complete = false;
  String? _email;
  String? _message;

  bool get _isReset => widget.mode == 'resetPassword';
  bool get _isOwnerReset => _isReset && widget.ownerPassword;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _pin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      if (_isReset) {
        _email = await (widget.verifyResetCode ??
            FirebaseAuth.instance.verifyPasswordResetCode)(widget.code);
        _ready = true;
      } else if (widget.mode == 'verifyEmail' ||
          widget.mode == 'verifyAndChangeEmail' ||
          widget.mode == 'recoverEmail') {
        await (widget.applyCode ?? FirebaseAuth.instance.applyActionCode)(
          widget.code,
        );
        _complete = true;
        _message = widget.mode == 'recoverEmail'
            ? 'Your previous email has been restored.'
            : 'Email verified successfully. Return to Enquiry Tracker and sign in with your mobile number and PIN.';
      } else {
        _message = 'This email link is not supported by Enquiry Tracker.';
      }
    } catch (error) {
      _message = error is FirebaseAuthException &&
              (error.code == 'expired-action-code' ||
                  error.code == 'invalid-action-code')
          ? 'This link is invalid or has expired. Request a new email from the app.'
          : recoveryMessage(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePin() async {
    final credentialIsValid = _isOwnerReset
        ? _pin.text.length >= 6 && _pin.text.length <= 128
        : RecoveryValidation.pin(_pin.text);
    if (!credentialIsValid) {
      setState(() => _message = _isOwnerReset
          ? 'Password must contain at least 6 characters.'
          : 'PIN must contain at least 6 digits.');
      return;
    }
    if (_pin.text != _confirmPin.text) {
      setState(() => _message =
          _isOwnerReset ? 'Passwords do not match.' : 'PINs do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final confirm = widget.confirmReset ??
          (String code, String pin) => FirebaseAuth.instance
              .confirmPasswordReset(code: code, newPassword: pin);
      await confirm(widget.code, _pin.text);
      if (mounted) {
        setState(() {
          _complete = true;
          _ready = false;
          _message = _isOwnerReset
              ? 'Password changed successfully. Return to Enquiry Tracker and sign in with your owner email and new password.'
              : 'PIN changed successfully. Return to Enquiry Tracker and sign in with your mobile number and new PIN.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = recoveryMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Enquiry Tracker account recovery')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    _complete
                        ? Icons.check_circle_outline
                        : Icons.lock_reset_outlined,
                    size: 52,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _isReset
                        ? (_isOwnerReset
                            ? 'Choose a new password'
                            : 'Choose a new PIN')
                        : 'Verify recovery email',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (_email != null) ...[
                    const SizedBox(height: 8),
                    Text(_email!, textAlign: TextAlign.center),
                  ],
                  if (_ready) ...[
                    const SizedBox(height: 22),
                    TextField(
                      controller: _pin,
                      enabled: !_busy,
                      obscureText: true,
                      keyboardType: _isOwnerReset
                          ? TextInputType.visiblePassword
                          : TextInputType.number,
                      inputFormatters: _isOwnerReset
                          ? [LengthLimitingTextInputFormatter(128)]
                          : [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(128),
                            ],
                      decoration: InputDecoration(
                        labelText: _isOwnerReset
                            ? 'New password (minimum 6 characters)'
                            : 'New PIN (minimum 6 digits)',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmPin,
                      enabled: !_busy,
                      obscureText: true,
                      keyboardType: _isOwnerReset
                          ? TextInputType.visiblePassword
                          : TextInputType.number,
                      inputFormatters: _isOwnerReset
                          ? [LengthLimitingTextInputFormatter(128)]
                          : [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(128),
                            ],
                      decoration: InputDecoration(
                        labelText: _isOwnerReset
                            ? 'Confirm new password'
                            : 'Confirm new PIN',
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _savePin,
                      child: Text(
                          _isOwnerReset ? 'Save new password' : 'Save new PIN'),
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 20),
                    const LinearProgressIndicator(),
                  ],
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Text(_message!, textAlign: TextAlign.center),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}
