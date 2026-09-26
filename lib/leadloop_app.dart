import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/customer_lead.dart';
import 'owner_home.dart';
import 'email_recovery_ui.dart';
import 'promoter_deletion_dialog.dart';
import 'sales_tracker_screen.dart';
import 'services/export_email_service.dart';
import 'services/export_file_downloader.dart';
import 'services/firebase_lead_backend.dart';
import 'services/firebase_sales_backend.dart';
import 'services/follow_up_deadline_service.dart';
import 'services/email_recovery_service.dart';
import 'services/leadloop_auth_service.dart';
import 'services/lead_export_service.dart';
import 'services/lead_search_service.dart';
import 'services/local_lead_store.dart';
import 'services/mobile_number_validator.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'services/workspace_state_store.dart';
import 'theme/app_theme.dart';

enum LeadloopRole { promoter, admin }

enum LeadStatusFilter { active, completed }

enum _OwnerHeaderAction { home, export, email, sync, theme, logout }

class LeadloopV2 extends StatefulWidget {
  const LeadloopV2({
    super.key,
    required this.store,
    this.ownerAccessEnabled,
  });

  final LocalLeadStore store;
  final bool? ownerAccessEnabled;

  @override
  State<LeadloopV2> createState() => _LeadloopV2State();
}

class _LeadloopV2State extends State<LeadloopV2> {
  static const _themeKey = 'enquiry_tracker_theme_mode';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ThemeData _lightTheme = AppTheme.light();
  final ThemeData _darkTheme = AppTheme.dark();
  ThemeMode _themeMode = ThemeMode.light;
  bool _brandAssetsCached = false;

  bool get _isDarkMode => _themeMode == ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _restoreTheme();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_brandAssetsCached) return;
    _brandAssetsCached = true;
    unawaited(Future.wait([
      precacheImage(
          const AssetImage('images/selvan_logo_transparent.png'), context),
      precacheImage(
          const AssetImage('images/selvan_logo_transparent_dark.png'), context),
    ]));
  }

  Future<void> _restoreTheme() async {
    try {
      final savedTheme = await _storage.read(key: _themeKey);
      if (!mounted || savedTheme == null) return;
      setState(() {
        _themeMode = savedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;
      });
    } catch (_) {
      // Keep the light default if storage is unavailable.
    }
  }

  void _toggleTheme() {
    final nextMode = _isDarkMode ? ThemeMode.light : ThemeMode.dark;
    setState(() => _themeMode = nextMode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_persistTheme(nextMode));
    });
  }

  Future<void> _persistTheme(ThemeMode nextMode) async {
    try {
      await _storage.write(
        key: _themeKey,
        value: nextMode == ThemeMode.dark ? 'dark' : 'light',
      );
    } catch (_) {
      // The visual change still works for the current session.
    }
  }

  @override
  Widget build(BuildContext context) {
    final emailAction = kIsWeb ? EmailActionScreen.fromUri(Uri.base) : null;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Enquiry Tracker',
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: _themeMode,
      themeAnimationDuration: Duration.zero,
      home: emailAction ??
          LeadloopAccessGate(
            store: widget.store,
            ownerAccessEnabled: widget.ownerAccessEnabled ?? kIsWeb,
            isDarkMode: _isDarkMode,
            onToggleTheme: _toggleTheme,
          ),
    );
  }
}

class LeadloopAccessGate extends StatefulWidget {
  const LeadloopAccessGate({
    super.key,
    required this.store,
    required this.ownerAccessEnabled,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  final LocalLeadStore store;
  final bool ownerAccessEnabled;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  @override
  State<LeadloopAccessGate> createState() => _LeadloopAccessGateState();
}

class _LeadloopAccessGateState extends State<LeadloopAccessGate>
    with WidgetsBindingObserver {
  static const _branches = ['Branch 1', 'Branch 2', 'Branch 3', 'Branch 4'];
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _recoveryEmailController = TextEditingController();
  bool _enterEmailOnce = false;
  String _selectedBranch = _branches.first;
  LeadloopAuthSession? _session;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileWatch;

  void _watchPromoter(LeadloopAuthSession? session) {
    _profileWatch?.cancel();
    _profileWatch = null;
    if (session == null || session.role != 'promoter') return;
    _profileWatch = FirebaseFirestore.instance
        .collection('promoters')
        .doc(session.uid)
        .snapshots()
        .listen((snapshot) {
      // Ignore an empty offline cache, but immediately block known disabled data.
      if (_session?.uid != session.uid) return;
      if ((!snapshot.exists && !snapshot.metadata.isFromCache) ||
          (snapshot.exists && snapshot.data()?['active'] != true)) {
        _blockPromoter();
      }
    }, onError: (Object error) {
      if (error is FirebaseException &&
          error.code == 'permission-denied' &&
          _session?.uid == session.uid) {
        _blockPromoter();
      }
    });
  }

  Future<void> _blockPromoter() async {
    if (!mounted || _session == null) return;
    _profileWatch?.cancel();
    _profileWatch = null;
    setState(() {
      _session = null;
      _pinController.clear();
      _error =
          'Your promoter account is disabled or deleted. Contact the owner.';
    });
    await _auth.clearBlockedSession();
  }

  bool _ownerMode = false;
  bool _registering = false;
  bool _busy = false;
  bool _restoring = true;
  String? _error;

  LeadloopAuthService? _authService;
  LeadloopAuthService get _auth => _authService ??= LeadloopAuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final session =
          Firebase.apps.isEmpty ? null : await _auth.restoreSession();
      if (!mounted) return;
      setState(() {
        _session = session;
        _restoring = false;
      });
      _watchPromoter(session);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _error = 'Could not restore the saved session: $error';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _session != null) {
      _auth.touchActivity();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _profileWatch?.cancel();
    _nameController.dispose();
    _mobileController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _recoveryEmailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = _ownerMode
          ? await _auth.signInAdmin(
              email: _emailController.text,
              password: _passwordController.text,
            )
          : await _auth.signInPromoter(
              mobile: _mobileController.text,
              pin: _pinController.text,
              email: _enterEmailOnce ? _recoveryEmailController.text : null,
            );
      if (!mounted) return;
      setState(() => _session = session);
      _watchPromoter(session);
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyAuthError(error));
    } on LeadloopAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Authentication failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    if (_busy) return;
    if (_pinController.text != _confirmPinController.text) {
      setState(() => _error = 'PINs do not match.');
      return;
    }
    if (!RecoveryValidation.pin(_pinController.text)) {
      setState(() => _error = 'PIN must contain at least 6 digits.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final hasRecoveryEmail = _recoveryEmailController.text.trim().isNotEmpty;
      await _auth.registerPromoter(
        name: _nameController.text,
        mobile: _mobileController.text,
        pin: _pinController.text,
        shopName: _selectedBranch,
        email: _recoveryEmailController.text,
      );
      await _auth.signOut();
      if (!mounted) return;
      setState(() {
        _registering = false;
        _error = hasRecoveryEmail
            ? 'Account created. Verify the email link and wait for owner approval before signing in.'
            : 'Account created. Wait for owner approval, then add a recovery email from Set up / verify recovery email.';
      });
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyAuthError(error));
    } on LeadloopAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Registration failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyAuthError(FirebaseAuthException error) {
    if (_ownerMode && !_registering) {
      return switch (error.code) {
        'invalid-email' => 'Enter a valid owner email address.',
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' =>
          'Owner email or password is incorrect.',
        'too-many-requests' =>
          'Too many sign-in attempts. Wait a moment and try again.',
        'network-request-failed' =>
          'Internet is required to sign in to the owner account.',
        _ => error.message ?? 'Owner authentication failed.',
      };
    }
    return switch (error.code) {
      'email-already-in-use' =>
        'This email is already registered. Sign in or use Forgot PIN.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' =>
        'Mobile number or PIN is incorrect. On a new device or after changing email, enter your email once using the option below.',
      'weak-password' => 'PIN must contain at least 6 digits.',
      'network-request-failed' =>
        'Internet is required for first-time authentication.',
      _ => error.message ?? 'Authentication failed.',
    };
  }

  Future<void> _logout() async {
    try {
      await _authService?.signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not sign out safely. Check your connection and try again.')));
      }
      return;
    }
    if (!mounted) return;
    _watchPromoter(null);
    setState(() {
      _session = null;
      _error = null;
      _pinController.clear();
      _passwordController.clear();
    });
  }

  Future<void> _setupRecoveryEmail() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.signInPromoter(
        mobile: _mobileController.text,
        pin: _pinController.text,
        email: _enterEmailOnce ? _recoveryEmailController.text : null,
        emailSetupOnly: true,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RecoveryEmailScreen()),
      );
      await _auth.clearBlockedSession();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is FirebaseAuthException
            ? _friendlyAuthError(error)
            : recoveryMessage(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _backToPromoterSignIn() {
    setState(() {
      _registering = false;
      _ownerMode = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final session = _session;
    if (session != null) {
      return TweenAnimationBuilder<double>(
        key: ValueKey('signed-in-${session.uid}'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: LeadloopShell(
          role: session.role == 'admin'
              ? LeadloopRole.admin
              : LeadloopRole.promoter,
          store: widget.store,
          session: session,
          onLogout: _logout,
          isDarkMode: widget.isDarkMode,
          onToggleTheme: widget.onToggleTheme,
        ),
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        ),
      );
    }
    return PopScope(
      canPop: !_registering && !_ownerMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && (_registering || _ownerMode)) {
          _backToPromoterSignIn();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: Card(
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _LoginBrandHeader(),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _registering
                                      ? 'Create your promoter account.'
                                      : _ownerMode
                                          ? 'Sign in with your owner account.'
                                          : 'Sign in with your mobile number and PIN.',
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                                ),
                              ),
                              SizedBox(
                                  height:
                                      !_registering && widget.ownerAccessEnabled
                                          ? 24
                                          : 10),
                              if (!_registering && widget.ownerAccessEnabled)
                                Wrap(spacing: 8, children: [
                                  ChoiceChip(
                                      label: const Text('Promoter'),
                                      selected: !_ownerMode,
                                      onSelected: (_) => setState(() {
                                            _ownerMode = false;
                                            _error = null;
                                          })),
                                  ChoiceChip(
                                      label: const Text('Owner'),
                                      selected: _ownerMode,
                                      onSelected: (_) => setState(() {
                                            _ownerMode = true;
                                            _error = null;
                                          })),
                                ]),
                              if (!_registering && !_ownerMode) ...[
                                if (widget.ownerAccessEnabled)
                                  const SizedBox(height: 16),
                                TextField(
                                    controller: _mobileController,
                                    keyboardType: TextInputType.phone,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(10),
                                    ],
                                    decoration: const InputDecoration(
                                        labelText: 'Mobile number')),
                                const SizedBox(height: 12),
                                TextField(
                                    controller: _pinController,
                                    obscureText: true,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(128),
                                    ],
                                    decoration: InputDecoration(
                                        labelText: 'Personal PIN',
                                        errorText: _error)),
                                if (_enterEmailOnce) ...[
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _recoveryEmailController,
                                    keyboardType: TextInputType.emailAddress,
                                    autocorrect: false,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Verified email (once on this device)',
                                    ),
                                  ),
                                ],
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    const ForgotPinScreen())),
                                    child: const Text('Forgot PIN?'),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                            _enterEmailOnce = !_enterEmailOnce;
                                            _error = null;
                                          }),
                                  child: Text(_enterEmailOnce
                                      ? 'Use remembered email / legacy login'
                                      : 'New device / email changed?'),
                                ),
                                TextButton(
                                  onPressed: _busy ? null : _setupRecoveryEmail,
                                  child: const Text(
                                      'Set up / verify recovery email'),
                                ),
                              ],
                              if (!_registering && _ownerMode) ...[
                                if (widget.ownerAccessEnabled)
                                  const SizedBox(height: 16),
                                TextField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: const InputDecoration(
                                        labelText: 'Owner email')),
                                const SizedBox(height: 12),
                                TextField(
                                    controller: _passwordController,
                                    obscureText: true,
                                    decoration: InputDecoration(
                                        labelText: 'Owner password',
                                        errorText: _error)),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    const OwnerForgotPasswordScreen(),
                                              ),
                                            ),
                                    child: const Text('Forgot password?'),
                                  ),
                                ),
                              ],
                              if (_registering) ...[
                                TextField(
                                    controller: _nameController,
                                    decoration: const InputDecoration(
                                        labelText: 'Full name')),
                                const SizedBox(height: 12),
                                TextField(
                                    controller: _mobileController,
                                    keyboardType: TextInputType.phone,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(10),
                                    ],
                                    decoration: const InputDecoration(
                                        labelText: 'Mobile number')),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedBranch,
                                  decoration: const InputDecoration(
                                      labelText: 'Shop name'),
                                  items: _branches
                                      .map((branch) => DropdownMenuItem(
                                            value: branch,
                                            child: Text(branch),
                                          ))
                                      .toList(growable: false),
                                  onChanged: (branch) {
                                    if (branch != null) {
                                      setState(() => _selectedBranch = branch);
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _recoveryEmailController,
                                  keyboardType: TextInputType.emailAddress,
                                  autocorrect: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Recovery email (optional)',
                                    helperText:
                                        'You can add and verify this later from your profile.',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                    controller: _pinController,
                                    obscureText: true,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(128),
                                    ],
                                    decoration: const InputDecoration(
                                        labelText: 'Create PIN (6+ digits)')),
                                const SizedBox(height: 12),
                                TextField(
                                    controller: _confirmPinController,
                                    obscureText: true,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(128),
                                    ],
                                    decoration: InputDecoration(
                                        labelText: 'Confirm PIN',
                                        errorText: _error)),
                              ],
                              const SizedBox(height: 14),
                              SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                      onPressed: _busy
                                          ? null
                                          : (_registering
                                              ? _register
                                              : _submit),
                                      child: Text(_busy
                                          ? 'Please wait...'
                                          : _registering
                                              ? 'Create promoter account'
                                              : 'Sign in'))),
                              const SizedBox(height: 10),
                              if (!_ownerMode || _registering)
                                TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() {
                                              _registering = !_registering;
                                              _error = null;
                                            }),
                                    child: Text(_registering
                                        ? 'Already registered? Sign in'
                                        : 'New promoter? Create an account')),
                              if (_error != null &&
                                  !_registering &&
                                  (_ownerMode ||
                                      _mobileController.text.isEmpty))
                                Text(_error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            tooltip: widget.isDarkMode
                                ? 'Switch to light theme'
                                : 'Switch to dark theme',
                            onPressed: widget.onToggleTheme,
                            icon: Icon(widget.isDarkMode
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_registering || _ownerMode)
              Positioned(
                top: 12,
                left: 12,
                child: SafeArea(
                  child: BackButton(onPressed: _backToPromoterSignIn),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class LeadloopShell extends StatefulWidget {
  const LeadloopShell({
    super.key,
    required this.role,
    required this.store,
    required this.session,
    required this.onLogout,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  final LeadloopRole role;
  final LocalLeadStore store;
  final LeadloopAuthSession session;
  final VoidCallback onLogout;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  @override
  State<LeadloopShell> createState() => _LeadloopShellState();
}

class _LeadloopShellState extends State<LeadloopShell> {
  int _tab = 0;
  bool _ownerFollowupOpen = false;
  bool _ownerSalesOpen = false;
  bool _ownerViewTouched = false;
  final WorkspaceStateStore _workspaceState = const WorkspaceStateStore();
  final ValueNotifier<int> _leadRevision = ValueNotifier(0);

  bool get _ownerModuleOpen => _ownerFollowupOpen || _ownerSalesOpen;

  void _ownerBack() => _openOwnerView(OwnerWorkspaceView.dashboard);

  void _applyOwnerView(OwnerWorkspaceView view) {
    _tab = view == OwnerWorkspaceView.promoters ? 1 : 0;
    _ownerFollowupOpen = view == OwnerWorkspaceView.followups ||
        view == OwnerWorkspaceView.promoters;
    _ownerSalesOpen = view == OwnerWorkspaceView.sales;
  }

  void _openOwnerView(OwnerWorkspaceView view) {
    _ownerViewTouched = true;
    setState(() => _applyOwnerView(view));
    unawaited(_workspaceState.writeOwnerView(view));
    if (view != OwnerWorkspaceView.sales) {
      unawaited(_workspaceState.writeSalesRecycleBin(false));
    }
    if (view != OwnerWorkspaceView.followups) {
      unawaited(_workspaceState.writeFollowupRecycleBin(false));
    }
    if (view != OwnerWorkspaceView.promoters) {
      unawaited(_workspaceState.writePromoterRecycleBin(false));
    }
  }

  Future<void> _restoreOwnerView() async {
    if (widget.role != LeadloopRole.admin) return;
    final view = await _workspaceState.readOwnerView();
    if (!mounted || _ownerViewTouched) return;
    setState(() => _applyOwnerView(view));
  }

  void _refreshLeadViews() {
    if (!mounted) return;
    _leadRevision.value++;
  }

  late final SyncService _syncService;
  late final FirebaseLeadBackend _firebaseBackend;
  late final FirebaseSalesBackend _salesBackend;
  final List<StreamSubscription> _leadSubscriptions = [];
  bool _exporting = false;
  bool _salesRetentionSweepComplete = false;
  Timer? _deadlineRefresh;
  StreamSubscription<RemoteMessage>? _messages;

  @override
  void initState() {
    super.initState();
    _firebaseBackend = FirebaseLeadBackend();
    _salesBackend = FirebaseSalesBackend();
    _syncService = SyncService();
    _syncService.start(syncPending: _syncNow);
    unawaited(_restoreOwnerView());
    NotificationService.instance.start(widget.session.uid);
    if (NotificationService.instance.supported) {
      _messages = FirebaseMessaging.onMessage.listen((message) {
        if (!mounted || message.data['recipientUid'] != widget.session.uid) {
          return;
        }
        final body = message.notification?.body;
        if (body != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(body)));
        }
      });
    }
    _deadlineRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      _refreshLeadViews();
    });
    if (_firebaseBackend.isConfigured) {
      unawaited(_startLeadWatch());
    }
  }

  Future<void> _startLeadWatch() async {
    final subscriptions = await _firebaseBackend.watchLeads(
      localStore: widget.store,
      userId: widget.session.uid,
      promoterId:
          widget.role == LeadloopRole.promoter ? widget.session.uid : null,
      onChanged: _refreshLeadViews,
    );
    if (!mounted) {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      return;
    }
    _leadSubscriptions.addAll(subscriptions);
  }

  Future<void> _syncNow() async {
    if (!_firebaseBackend.isConfigured) return;
    try {
      if (widget.role == LeadloopRole.admin) {
        await _firebaseBackend.syncAdmin(widget.store);
        if (!_salesRetentionSweepComplete) {
          await _salesBackend.permanentlyDeleteExpiredRecycledData();
          _salesRetentionSweepComplete = true;
        }
      } else {
        await _firebaseBackend.syncPromoter(widget.store, widget.session.uid);
      }
      _refreshLeadViews();
    } catch (error, stackTrace) {
      // The local store remains usable. The next connectivity event retries.
      debugPrint('Lead sync failed: $error\n$stackTrace');
      rethrow;
    }
  }

  Future<void> _manualSyncNow() async {
    try {
      await _syncNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dashboard refreshed.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync could not complete. Check your connection.'),
        ),
      );
    }
  }

  Future<void> _handleOwnerHeaderAction(_OwnerHeaderAction action) async {
    switch (action) {
      case _OwnerHeaderAction.home:
        _ownerBack();
        return;
      case _OwnerHeaderAction.export:
        await _exportCustomers(email: false);
        return;
      case _OwnerHeaderAction.email:
        await _exportCustomers(email: true);
        return;
      case _OwnerHeaderAction.sync:
        await _manualSyncNow();
        return;
      case _OwnerHeaderAction.theme:
        widget.onToggleTheme();
        return;
      case _OwnerHeaderAction.logout:
        widget.onLogout();
        return;
    }
  }

  Future<void> _exportCustomers({required bool email}) async {
    if (_exporting) return;

    String? recipient;
    if (email) {
      recipient = await _askForEmail();
      if (recipient == null) return;
    }

    setState(() => _exporting = true);
    try {
      await _syncService.syncNow();
      if (!mounted) return;

      final downloadedAt = DateTime.now();
      final fileName =
          'Tracking ${downloadedAt.day.toString().padLeft(2, '0')}-${downloadedAt.month.toString().padLeft(2, '0')}-${downloadedAt.year}.xlsx';
      final bytes = LeadExportService().buildWorkbook(
        activeLeads: widget.store.activeLeads(),
        deletedLeads: widget.store.recycleBin(),
      );

      if (email) {
        const subject = 'Enquiry Tracker customer follow-ups';
        if (kIsWeb) {
          await downloadExcelExport(bytes, fileName);
          final opened = await ExportEmailService.composeWebEmail(
            recipient: recipient!,
            subject: subject,
            body: 'The Excel export has been downloaded as “$fileName”.\n\n'
                'Please attach that file to this email before sending.',
          );
          if (mounted) {
            _showExportMessage(opened
                ? 'Excel downloaded and email draft opened. Attach $fileName before sending.'
                : 'Excel downloaded as $fileName. Open your email and attach it before sending.');
          }
          return;
        }

        final opened = await ExportEmailService.composeAndroidEmail(
          recipient: recipient!,
          subject: subject,
          body: 'Attached is the latest Enquiry Tracker customer export.',
          fileName: fileName,
          bytes: bytes,
        );
        if (opened) {
          if (mounted) {
            _showExportMessage(
                'Email draft opened with the Excel export attached.');
          }
          return;
        }

        final result = await SharePlus.instance.share(
          ShareParams(
            title: 'Email customer export',
            subject: subject,
            text: 'Send this Excel export to $recipient.',
            files: [
              XFile.fromData(
                bytes,
                name: fileName,
                mimeType:
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              ),
            ],
            fileNameOverrides: [fileName],
            downloadFallbackEnabled: true,
            mailToFallbackEnabled: true,
          ),
        );
        if (mounted) {
          _showExportMessage(result.status == ShareResultStatus.dismissed
              ? 'Email export was cancelled.'
              : 'Choose your email app to send the attached Excel export.');
        }
        return;
      }

      if (kIsWeb) {
        await downloadExcelExport(bytes, fileName);
        if (mounted) {
          _showExportMessage('Excel export downloaded successfully.');
        }
        return;
      }

      final result = await SharePlus.instance.share(
        ShareParams(
          title: 'Export customer data',
          subject: 'Enquiry Tracker customer follow-ups',
          text: 'Enquiry Tracker customer follow-up export',
          files: [
            XFile.fromData(
              bytes,
              name: fileName,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          fileNameOverrides: [fileName],
          downloadFallbackEnabled: true,
          mailToFallbackEnabled: true,
        ),
      );
      if (!mounted) return;
      _showExportMessage(result.status == ShareResultStatus.dismissed
          ? 'Export was cancelled.'
          : 'Choose where to save or share the Excel export.');
    } catch (error) {
      debugPrint('Customer export${email ? ' email' : ''} failed: $error');
      if (mounted) {
        _showExportMessage(email
            ? 'Could not send the Excel email. Check the email service setup and try again.'
            : 'Could not create the Excel export. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showExportMessage(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<String?> _askForEmail() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send export by email'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Recipient email'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Continue')),
        ],
      ),
    );
    controller.dispose();
    if (email == null || !RecoveryValidation.email(email)) {
      if (email != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a valid email address.')));
      }
      return null;
    }
    return email;
  }

  @override
  void dispose() {
    for (final subscription in _leadSubscriptions) {
      subscription.cancel();
    }
    _deadlineRefresh?.cancel();
    _messages?.cancel();
    NotificationService.instance.stop();
    _syncService.dispose();
    _leadRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.role == LeadloopRole.admin;
    final compactHeader = MediaQuery.sizeOf(context).width < 720;
    final destinations = isAdmin
        ? const <NavigationDestination>[
            NavigationDestination(
                icon: Icon(Icons.dashboard_outlined), label: 'Admin'),
            NavigationDestination(
                icon: Icon(Icons.groups_outlined), label: 'Promoters'),
          ]
        : const <NavigationDestination>[
            NavigationDestination(
                icon: Icon(Icons.person_outline), label: 'Promoter')
          ];
    final Widget workspaceBody;
    if (isAdmin && _ownerSalesOpen) {
      workspaceBody = SalesTrackerScreen(
        backend: _salesBackend,
        ownerUid: widget.session.uid,
        ownerName: widget.session.displayName,
      );
    } else {
      workspaceBody = ValueListenableBuilder<int>(
        valueListenable: _leadRevision,
        builder: (context, _, __) {
          if (isAdmin && !_ownerModuleOpen) {
            return OwnerHome(
              leads: widget.store.activeLeads(),
              onFollowup: () => _openOwnerView(OwnerWorkspaceView.followups),
              onSales: kIsWeb
                  ? () => _openOwnerView(OwnerWorkspaceView.sales)
                  : null,
            );
          }
          final pages = isAdmin
              ? <Widget>[
                  LeadloopAdminScreen(
                      store: widget.store,
                      backend: _firebaseBackend,
                      onChanged: _syncService.syncNow),
                  LeadloopPromoterAdminScreen(backend: _firebaseBackend),
                ]
              : <Widget>[
                  LeadloopPromoterScreen(
                      store: widget.store,
                      onChanged: _syncService.syncNow,
                      promoterId: widget.session.uid,
                      promoterName: widget.session.displayName,
                      shopId: widget.session.shopId,
                      shopName: widget.session.shopName,
                      syncStatusListenable: _syncService.status)
                ];
          return IndexedStack(index: _tab, children: pages);
        },
      );
    }
    final workspaceKey = !isAdmin
        ? 'promoter'
        : _ownerSalesOpen
            ? 'sales'
            : !_ownerModuleOpen
                ? 'dashboard'
                : 'followup-workspace';
    return PopScope(
      canPop: !isAdmin || !_ownerModuleOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isAdmin && _ownerModuleOpen) {
          _ownerBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
            toolbarHeight: 84,
            titleSpacing: isAdmin ? null : 12,
            leading: isAdmin && _ownerModuleOpen
                ? BackButton(onPressed: _ownerBack)
                : null,
            title: isAdmin
                ? _OwnerBrandLogo(onTap: _ownerBack)
                : const _PromoterBrandHeader(),
            actions: [
              if (isAdmin && compactHeader)
                PopupMenuButton<_OwnerHeaderAction>(
                  tooltip: 'More actions',
                  onSelected: (action) =>
                      unawaited(_handleOwnerHeaderAction(action)),
                  itemBuilder: (context) => [
                    if (_ownerModuleOpen)
                      const PopupMenuItem(
                        value: _OwnerHeaderAction.home,
                        child: _HeaderMenuItem(
                            icon: Icons.home_outlined, label: 'Home'),
                      ),
                    if (_ownerFollowupOpen)
                      PopupMenuItem(
                        value: _OwnerHeaderAction.export,
                        enabled: !_exporting,
                        child: const _HeaderMenuItem(
                            icon: Icons.table_view_outlined,
                            label: 'Export to Excel'),
                      ),
                    if (_ownerFollowupOpen)
                      PopupMenuItem(
                        value: _OwnerHeaderAction.email,
                        enabled: !_exporting,
                        child: const _HeaderMenuItem(
                            icon: Icons.email_outlined,
                            label: 'Email Excel export'),
                      ),
                    if (_firebaseBackend.isConfigured && _ownerFollowupOpen)
                      const PopupMenuItem(
                        value: _OwnerHeaderAction.sync,
                        child: _HeaderMenuItem(
                            icon: Icons.sync_outlined, label: 'Sync now'),
                      ),
                    PopupMenuItem(
                      value: _OwnerHeaderAction.theme,
                      child: _HeaderMenuItem(
                        icon: widget.isDarkMode
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        label: widget.isDarkMode ? 'Light theme' : 'Dark theme',
                      ),
                    ),
                    const PopupMenuItem(
                      value: _OwnerHeaderAction.logout,
                      child:
                          _HeaderMenuItem(icon: Icons.logout, label: 'Logout'),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert),
                )
              else ...[
                if (isAdmin && _ownerModuleOpen)
                  IconButton(
                    tooltip: 'Home',
                    onPressed: _ownerBack,
                    icon: const Icon(Icons.home_outlined),
                  ),
                if (isAdmin && _ownerFollowupOpen) ...[
                  IconButton(
                      tooltip: 'Export to Excel',
                      onPressed: _exporting
                          ? null
                          : () => _exportCustomers(email: false),
                      icon: const Icon(Icons.table_view_outlined)),
                  IconButton(
                      tooltip: 'Send Excel by email',
                      onPressed: _exporting
                          ? null
                          : () => _exportCustomers(email: true),
                      icon: const Icon(Icons.email_outlined)),
                ],
                if (!isAdmin)
                  ValueListenableBuilder<LeadloopSyncStatus>(
                    valueListenable: _syncService.status,
                    builder: (context, status, _) {
                      final synced = status == LeadloopSyncStatus.synced;
                      return Tooltip(
                        message:
                            synced ? 'Synced to Firebase' : 'Saved locally',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(
                            synced
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined,
                            color: synced
                                ? AppColors.successFor(
                                    Theme.of(context).brightness)
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                      );
                    },
                  ),
                if (!isAdmin)
                  IconButton(
                    tooltip: 'Set up recovery email',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RecoveryEmailScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.mark_email_read_outlined),
                  ),
                if (_firebaseBackend.isConfigured &&
                    (!isAdmin || _ownerFollowupOpen))
                  IconButton(
                      tooltip: 'Sync now',
                      onPressed: _manualSyncNow,
                      icon: const Icon(Icons.sync_outlined)),
                IconButton(
                    tooltip: widget.isDarkMode
                        ? 'Switch to light theme'
                        : 'Switch to dark theme',
                    onPressed: widget.onToggleTheme,
                    icon: Icon(widget.isDarkMode
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined)),
                IconButton(
                    tooltip: isAdmin ? 'Logout' : 'Lock app',
                    onPressed: widget.onLogout,
                    icon: Icon(isAdmin ? Icons.logout : Icons.lock_outline)),
              ],
            ]),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            reverseDuration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.018, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(workspaceKey),
              child: workspaceBody,
            ),
          ),
        ),
        // Flutter requires NavigationBar to have at least two destinations.
        // Promoters have one screen, so navigation is only shown to owners.
        bottomNavigationBar:
            destinations.length < 2 || (isAdmin && !_ownerFollowupOpen)
                ? null
                : NavigationBar(
                    selectedIndex: _tab,
                    onDestinationSelected: (index) => _openOwnerView(
                          index == 0
                              ? OwnerWorkspaceView.followups
                              : OwnerWorkspaceView.promoters,
                        ),
                    destinations: destinations),
      ),
    );
  }
}

class _LoginBrandHeader extends StatelessWidget {
  const _LoginBrandHeader();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth.clamp(0.0, 330.0)
            : 330.0;
        return SizedBox(
          width: width,
          height: 132,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Image.asset(
                  dark
                      ? 'images/selvan_logo_transparent_dark.png'
                      : 'images/selvan_logo_transparent.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(height: 6),
              const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  'Enquiry Tracker',
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OwnerBrandLogo extends StatelessWidget {
  const _OwnerBrandLogo({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'Selvan Steel House — go to dashboard',
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.hasBoundedWidth
                  ? constraints.maxWidth.clamp(0.0, 300.0)
                  : 300.0;
              return SizedBox(
                width: width,
                height: 76,
                child: Image.asset(
                  dark
                      ? 'images/selvan_logo_transparent_dark.png'
                      : 'images/selvan_logo_transparent.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  filterQuality: FilterQuality.high,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PromoterBrandHeader extends StatelessWidget {
  const _PromoterBrandHeader();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth.clamp(0.0, 180.0)
            : 180.0;
        return SizedBox(
          width: availableWidth,
          height: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Image.asset(
                  dark
                      ? 'images/selvan_logo_transparent_dark.png'
                      : 'images/selvan_logo_transparent.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(height: 2),
              const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Enquiry Tracker',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderMenuItem extends StatelessWidget {
  const _HeaderMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ],
      );
}

class LeadloopPromoterScreen extends StatefulWidget {
  const LeadloopPromoterScreen(
      {super.key,
      required this.store,
      required this.promoterId,
      required this.promoterName,
      required this.shopId,
      required this.shopName,
      required this.syncStatusListenable,
      this.onChanged});

  final LocalLeadStore store;
  final String promoterId;
  final String promoterName;
  final String shopId;
  final String shopName;
  final ValueListenable<LeadloopSyncStatus> syncStatusListenable;
  final Future<void> Function()? onChanged;

  @override
  State<LeadloopPromoterScreen> createState() => _LeadloopPromoterScreenState();
}

class _LeadloopPromoterScreenState extends State<LeadloopPromoterScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _comment = TextEditingController();
  final _search = TextEditingController();
  FollowUpStage? _stage;
  int _visibleRecordCount = 15;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _comment.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Name and mobile number are required.')));
      return;
    }
    if (!MobileNumberValidator.isValid(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(MobileNumberValidator.errorMessage)));
      return;
    }
    final savedAt = DateTime.now();
    final firstComment = _comment.text.trim();
    await widget.store.save(CustomerLead(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      phone: phone,
      shopName: widget.shopName,
      promoterName: widget.promoterName,
      shopId: widget.shopId,
      promoterId: widget.promoterId,
      createdAt: savedAt,
      followUp1: firstComment.isEmpty ? null : firstComment,
      followUp1At: firstComment.isEmpty ? null : savedAt,
    ));
    await widget.onChanged?.call();
    _name.clear();
    _phone.clear();
    _comment.clear();
    if (!mounted) return;
    setState(() {});
    final message =
        widget.syncStatusListenable.value == LeadloopSyncStatus.synced
            ? 'Synced to Database.'
            : 'Saved locally.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _call(String phone) =>
      launchUrl(Uri(scheme: 'tel', path: phone));

  Future<void> _openLead(CustomerLead lead) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => LeadloopFollowUpScreen(
                store: widget.store, lead: lead, onChanged: widget.onChanged)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // The local Hive box can contain records from previous sessions on a
    // shared device. Promoters must only see records created by their UID.
    final allLeads = widget.store
        .activeLeads()
        .where((lead) => lead.promoterId == widget.promoterId)
        .toList();
    final overdueFollowUp2 =
        allLeads.where(FollowUpDeadlineService.isOverdue).toList();
    final query = _search.text.trim().toLowerCase();
    final leads = allLeads
        .where((lead) =>
            query.isNotEmpty || _stage == null || lead.currentStage == _stage)
        .where((lead) => LeadSearchService.matches(lead, query))
        .toList();
    final visibleLeads =
        leads.take(_visibleRecordCount).toList(growable: false);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        Text('PROMOTER · ${widget.shopName.toUpperCase()}',
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 11,
                letterSpacing: 1.1)),
        if (overdueFollowUp2.isNotEmpty) ...[
          const SizedBox(height: 10),
          _FollowUp2OverdueBanner(
            leads: overdueFollowUp2,
            promoterSummary: true,
          ),
        ],
        const SizedBox(height: 17),
        TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Customer name')),
        const SizedBox(height: 12),
        TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: const InputDecoration(labelText: 'Mobile number')),
        const SizedBox(height: 12),
        TextField(
            controller: _comment,
            minLines: 1,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Follow-up 1 comment',
                hintText: 'Optional for now')),
        const SizedBox(height: 15),
        FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save customer'),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14))),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() => _visibleRecordCount = 15),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Search customers and comments',
            hintText: 'Name, mobile number or follow-up text',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _search.clear();
                      setState(() => _visibleRecordCount = 15);
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 24),
        Row(children: [
          const Text('Recent customers',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${visibleLeads.length} shown · ${allLeads.length} total',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12))
        ]),
        const SizedBox(height: 10),
        _FollowUpStageButtons(
          selected: _stage,
          onSelected: (stage) => setState(() {
            _stage = stage;
            _visibleRecordCount = 15;
          }),
        ),
        const SizedBox(height: 8),
        if (leads.isEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                  allLeads.isEmpty
                      ? 'Your saved customers will appear here.'
                      : 'No customers are currently in this follow-up stage.',
                  textAlign: TextAlign.center))
        else
          ...visibleLeads.map((lead) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PromoterLeadCard(
                  lead: lead,
                  onOpen: () => _openLead(lead),
                  onCall: () => _call(lead.phone),
                ),
              )),
        if (visibleLeads.length < leads.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: FilledButton.tonalIcon(
                onPressed: () => setState(() => _visibleRecordCount += 15),
                icon: const Icon(Icons.expand_more),
                label: Text(
                  'Load more (${leads.length - visibleLeads.length} remaining)',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class LeadloopFollowUpScreen extends StatefulWidget {
  const LeadloopFollowUpScreen(
      {super.key,
      required this.store,
      required this.lead,
      this.onChanged,
      this.isNewEnquiry = false});

  final LocalLeadStore store;
  final CustomerLead lead;
  final bool isNewEnquiry;
  final Future<void> Function()? onChanged;

  @override
  State<LeadloopFollowUpScreen> createState() => _LeadloopFollowUpScreenState();
}

class _LeadloopFollowUpScreenState extends State<LeadloopFollowUpScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _first;
  late final TextEditingController _second;
  late final TextEditingController _third;
  bool _creatingEnquiry = false;
  bool _saving = false;
  late CustomerLead _lead;
  late EnquiryOutcome _outcome;
  final _nextComment = TextEditingController();
  final List<TextEditingController> _extraComments = [];
  bool _addingFollowUp = false;

  @override
  void initState() {
    super.initState();
    _lead = widget.lead;
    _outcome = _lead.outcome;
    _name = TextEditingController(text: _lead.name);
    _phone = TextEditingController(text: _lead.phone);
    _first = TextEditingController(text: _lead.followUp1 ?? '');
    _second = TextEditingController(text: _lead.followUp2 ?? '');
    _third = TextEditingController(text: _lead.followUp3 ?? '');
    _extraComments.addAll(_lead.additionalFollowUps
        .map((entry) => TextEditingController(text: entry.comment)));
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _first.dispose();
    _second.dispose();
    _third.dispose();
    _nextComment.dispose();
    for (final controller in _extraComments) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _creatingEnquiry) return;
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Name and mobile number are required.')));
      return;
    }
    if (!MobileNumberValidator.isValid(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(MobileNumberValidator.errorMessage)));
      return;
    }
    final savedAt = DateTime.now();
    final first = _first.text.trim();
    final second = _second.text.trim();
    final third = _third.text.trim();
    if (second.isNotEmpty && first.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Save Follow-up 1 before entering Follow-up 2.')));
      return;
    }
    if (third.isNotEmpty && second.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Save Follow-up 2 before entering Follow-up 3.')));
      return;
    }
    if (_lead.additionalFollowUps.isNotEmpty && third.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Follow-up 3 is required before later follow-ups.')));
      return;
    }
    final next = _nextComment.text.trim();
    if (_extraComments.any((controller) => controller.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Saved follow-ups cannot be left blank.')));
      return;
    }
    if (_addingFollowUp && next.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter the next follow-up comment before saving.')));
      return;
    }
    final commentsUnchanged =
        _extraComments.length == _lead.additionalFollowUps.length &&
            List.generate(
              _extraComments.length,
              (index) =>
                  _extraComments[index].text.trim() ==
                  _lead.additionalFollowUps[index].comment,
            ).every((unchanged) => unchanged);
    final unchanged = !_addingFollowUp &&
        name == _lead.name &&
        phone == _lead.phone &&
        first == (_lead.followUp1 ?? '') &&
        second == (_lead.followUp2 ?? '') &&
        third == (_lead.followUp3 ?? '') &&
        _outcome == _lead.outcome &&
        commentsUnchanged;
    if (unchanged) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No changes to save.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = _lead.copyWith(
        outcome: _outcome,
        completedAt: _outcome != EnquiryOutcome.active
            ? (_lead.completedAt ?? savedAt)
            : null,
        additionalFollowUps: [
          for (var i = 0; i < _lead.additionalFollowUps.length; i++)
            FollowUpEntry(
                comment: _extraComments[i].text.trim(),
                enteredAt: _extraComments[i].text.trim() ==
                        _lead.additionalFollowUps[i].comment
                    ? _lead.additionalFollowUps[i].enteredAt
                    : savedAt),
          if (_addingFollowUp) FollowUpEntry(comment: next, enteredAt: savedAt),
        ],
        name: name,
        phone: phone,
        followUp1: first,
        followUp1At:
            _commentTime(_lead.followUp1, first, _lead.followUp1At, savedAt),
        followUp2: second,
        followUp2At:
            _commentTime(_lead.followUp2, second, _lead.followUp2At, savedAt),
        followUp3: third,
        followUp3At:
            _commentTime(_lead.followUp3, third, _lead.followUp3At, savedAt),
        isSynced: false,
      );
      await widget.store.save(updated);
      if (_addingFollowUp) {
        _extraComments.add(TextEditingController(text: next));
      }
      _lead = updated;
      _addingFollowUp = false;
      _nextComment.clear();
      await widget.onChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Follow-ups saved.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not finish saving. Check the record and try again.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createNewEnquiry() async {
    if (_creatingEnquiry || _saving) return;
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Name and mobile number are required.')));
      return;
    }
    if (!MobileNumberValidator.isValid(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(MobileNumberValidator.errorMessage)));
      return;
    }

    setState(() => _creatingEnquiry = true);
    try {
      final newLead = CustomerLead(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        phone: phone,
        shopName: _lead.shopName,
        promoterName: _lead.promoterName,
        shopId: _lead.shopId,
        promoterId: _lead.promoterId,
        createdAt: DateTime.now(),
      );
      await widget.store.save(newLead);
      await widget.onChanged?.call();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LeadloopFollowUpScreen(
            store: widget.store,
            lead: newLead,
            isNewEnquiry: true,
            onChanged: widget.onChanged,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _creatingEnquiry = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create the enquiry: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.isNewEnquiry ? 'New enquiry' : 'Edit customer')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text(widget.isNewEnquiry ? 'New enquiry' : 'Customer details',
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Customer name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: const InputDecoration(labelText: 'Mobile number'),
            ),
            const SizedBox(height: 8),
            Text('Entered ${_formatDateTime(_lead.createdAt)}',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12)),
            if (FollowUpDeadlineService.isOverdue(_lead)) ...[
              const SizedBox(height: 12),
              _FollowUp2OverdueBanner(leads: [_lead]),
            ],
            const SizedBox(height: 22),
            _LeadloopFollowUpField(
              label: 'Follow-up 1',
              controller: _first,
              enteredAt: _lead.followUp1At,
            ),
            const SizedBox(height: 14),
            _LeadloopFollowUpField(
              label: 'Follow-up 2',
              controller: _second,
              enteredAt: _lead.followUp2At,
              enabled: _lead.followUp1?.trim().isNotEmpty == true,
              lockedMessage: 'Save Follow-up 1 to unlock this comment',
            ),
            const SizedBox(height: 14),
            _LeadloopFollowUpField(
              label: 'Follow-up 3',
              controller: _third,
              enteredAt: _lead.followUp3At,
              enabled: _lead.followUp2?.trim().isNotEmpty == true,
              lockedMessage: 'Save Follow-up 2 to unlock this comment',
            ),
            for (var i = 0; i < _lead.additionalFollowUps.length; i++) ...[
              const SizedBox(height: 14),
              _LeadloopFollowUpField(
                  label: 'Follow-up ${i + 4}',
                  controller: _extraComments[i],
                  enteredAt: _lead.additionalFollowUps[i].enteredAt),
            ],
            if (!_lead.isCompleted &&
                _lead.followUp3?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 14),
              if (!_addingFollowUp)
                TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () => setState(() => _addingFollowUp = true),
                  icon: const Icon(Icons.add),
                  label: Text('Add follow-up ${_lead.followUpNumber + 1}'),
                )
              else
                TextField(
                    controller: _nextComment,
                    maxLines: 2,
                    decoration: InputDecoration(
                        labelText: 'Follow-up ${_lead.followUpNumber + 1}')),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<EnquiryOutcome>(
              initialValue: _outcome,
              decoration: const InputDecoration(labelText: 'Enquiry status'),
              items: EnquiryOutcome.values
                  .map((outcome) => DropdownMenuItem(
                      value: outcome,
                      child: Text(switch (outcome) {
                        EnquiryOutcome.active => 'Active',
                        EnquiryOutcome.purchased => 'Purchased',
                        EnquiryOutcome.closedWithoutPurchase =>
                          'Closed without purchase',
                      })))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _outcome = value);
                    },
            ),
            if (_lead.completedAt != null && _lead.isCompleted)
              Text('Completed ${_formatDateTime(_lead.completedAt)}'),
            const SizedBox(height: 20),
            FilledButton.icon(
                onPressed: _saving || _creatingEnquiry ? null : _save,
                icon: const Icon(Icons.check),
                label: const Text('Save follow-ups'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14))),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _creatingEnquiry ? null : _createNewEnquiry,
              icon: const Icon(Icons.add),
              label: Text(_creatingEnquiry
                  ? 'Creating enquiry...'
                  : 'New enquiry for this customer'),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
        ),
      );

  DateTime? _commentTime(
    String? previousText,
    String currentText,
    DateTime? previousTime,
    DateTime savedAt,
  ) {
    if (currentText.isEmpty) return previousTime;
    return previousText?.trim() == currentText ? previousTime : savedAt;
  }
}

class LeadloopAdminScreen extends StatefulWidget {
  const LeadloopAdminScreen(
      {super.key, required this.store, required this.backend, this.onChanged});

  final LocalLeadStore store;
  final FirebaseLeadBackend backend;
  final Future<void> Function()? onChanged;

  @override
  State<LeadloopAdminScreen> createState() => _LeadloopAdminScreenState();
}

class _LeadloopAdminScreenState extends State<LeadloopAdminScreen> {
  final Map<String, _LeadCommentLayout> _commentLayouts = {};
  final WorkspaceStateStore _workspaceState = const WorkspaceStateStore();
  bool _showRecycleBin = false;
  bool _recycleBinTouched = false;
  String? _shop;
  String? _promoter;
  FollowUpStage? _stage;
  DateTimeRange? _dateRange;
  LeadStatusFilter? _status;
  int _visibleRecordCount = 15;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreRecycleBin());
  }

  Future<void> _restoreRecycleBin() async {
    final visible = await _workspaceState.readFollowupRecycleBin();
    if (!mounted || _recycleBinTouched || !visible) return;
    setState(() => _showRecycleBin = true);
  }

  void _setRecycleBinVisible(bool visible) {
    _recycleBinTouched = true;
    setState(() => _showRecycleBin = visible);
    unawaited(_workspaceState.writeFollowupRecycleBin(visible));
  }

  List<CustomerLead> _filterLeads(Iterable<CustomerLead> source) {
    final start = _dateRange == null
        ? null
        : DateTime(
            _dateRange!.start.year,
            _dateRange!.start.month,
            _dateRange!.start.day,
          );
    final end = _dateRange == null
        ? null
        : DateTime(
            _dateRange!.end.year,
            _dateRange!.end.month,
            _dateRange!.end.day + 1,
          );
    return source
        .where((lead) =>
            (_shop == null || lead.shopName == _shop) &&
            (_promoter == null || lead.promoterName == _promoter) &&
            (_stage == null || lead.currentStage == _stage) &&
            (start == null || !lead.createdAt.isBefore(start)) &&
            (end == null || lead.createdAt.isBefore(end)) &&
            (_status == null ||
                (_status == LeadStatusFilter.completed) == lead.isCompleted))
        .toList();
  }

  bool get _hasActiveFilters =>
      _dateRange != null ||
      _promoter != null ||
      _shop != null ||
      _stage != null ||
      _status != null;

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _dateRange,
      helpText: 'FILTER BY ENTRY DATE',
    );
    if (selected != null && mounted) {
      setState(() {
        _dateRange = selected;
        _visibleRecordCount = 15;
      });
    }
  }

  Future<void> _edit(CustomerLead lead) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeadloopFollowUpScreen(
          store: widget.store,
          lead: lead,
          onChanged: widget.onChanged,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _delete(CustomerLead lead) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to recycle bin?'),
        content: Text(
            '${lead.name} will leave active customer lists and can be restored later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Move')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.softDelete(lead.id);
    await widget.onChanged?.call();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _deleteFiltered() async {
    final leads = _filterLeads(widget.store.activeLeads());
    if (leads.isEmpty) return;
    final isFilteredDelete = _hasActiveFilters;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isFilteredDelete
            ? 'Move ${leads.length} filtered records?'
            : 'Move all ${leads.length} active records?'),
        content: Text(isFilteredDelete
            ? 'Every record matching the current filters will move to the recycle bin and can be restored later.'
            : 'Every active customer enquiry will move to the recycle bin and can be restored later. Nothing will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Move records')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.softDeleteMany(leads.map((lead) => lead.id));
    await widget.onChanged?.call();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${leads.length} records moved to the recycle bin.')));
  }

  Future<void> _transfer(CustomerLead lead) async {
    final promoters = (await widget.backend.listPromoters())
        .where((promoter) => promoter.active && promoter.uid != lead.promoterId)
        .toList();
    if (!mounted) return;
    if (promoters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No other active promoter is available.')));
      return;
    }

    final selected = await showDialog<LeadloopPromoterProfile>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pass lead to promoter'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: promoters
                .map((promoter) => ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(promoter.name),
                      subtitle: Text(promoter.shopName),
                      onTap: () => Navigator.pop(context, promoter),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (selected == null) return;

    await widget.backend.transferLead(lead: lead, promoter: selected);
    await widget.store.saveFromServer(lead.copyWith(
      promoterId: selected.uid,
      promoterName: selected.name,
      shopId: selected.shopId,
      shopName: selected.shopName,
    ));
    await widget.onChanged?.call();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lead passed to ${selected.name}.')));
  }

  Future<void> _showOverdueSummary(List<CustomerLead> overdueLeads) async {
    final grouped = <String, List<CustomerLead>>{};
    for (final lead in overdueLeads) {
      final key = lead.promoterId.trim().isNotEmpty
          ? lead.promoterId
          : lead.promoterName.trim().toLowerCase();
      grouped.putIfAbsent(key, () => []).add(lead);
    }
    final summaries = grouped.values.map((leads) {
      leads.sort((a, b) {
        final aDue = FollowUpDeadlineService.nextDueAt(a);
        final bDue = FollowUpDeadlineService.nextDueAt(b);
        if (aDue == null && bDue == null) return 0;
        if (aDue == null) return 1;
        if (bDue == null) return -1;
        return aDue.compareTo(bDue);
      });
      return _PromoterOverdueSummary(
        promoterName: leads.first.promoterName,
        shopName: leads.first.shopName,
        leads: leads,
      );
    }).toList()
      ..sort((a, b) =>
          a.promoterName.toLowerCase().compareTo(b.promoterName.toLowerCase()));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Overdue follow-ups by promoter'),
        content: SizedBox(
          width: 620,
          child: summaries.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No promoters currently have overdue follow-ups.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: summaries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final summary = summaries[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      leading: CircleAvatar(
                        child: Text(summary.promoterName.isEmpty
                            ? '?'
                            : summary.promoterName[0].toUpperCase()),
                      ),
                      title: Text(
                        summary.promoterName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(summary.shopName),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${summary.leads.length} overdue',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(dialogContext);
                        unawaited(_showPromoterOverdue(summary));
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPromoterOverdue(
    _PromoterOverdueSummary summary,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text('${summary.promoterName} · ${summary.leads.length} overdue'),
        content: SizedBox(
          width: 680,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: summary.leads.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final lead = summary.leads[index];
              final dueAt = FollowUpDeadlineService.nextDueAt(lead);
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 5,
                ),
                title: Text(
                  lead.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${lead.phone}\nFollow-up ${lead.followUpNumber + 1} due ${dueAt == null ? '—' : _formatDateTime(dueAt)}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.edit_outlined),
                onTap: () {
                  Navigator.pop(dialogContext);
                  unawaited(_edit(lead));
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showRecycleBin) {
      return LeadloopRecycleBinScreen(
        store: widget.store,
        backend: widget.backend,
        onChanged: widget.onChanged,
        onBack: () => _setRecycleBinVisible(false),
      );
    }
    final all = widget.store.activeLeads();
    final leads = _filterLeads(all);
    final visibleLeads =
        leads.take(_visibleRecordCount).toList(growable: false);
    final overdueFollowUp2 =
        all.where(FollowUpDeadlineService.isOverdue).toList();
    final shops = all.map((lead) => lead.shopName).toSet().toList()..sort();
    final promoters = all.map((lead) => lead.promoterName).toSet().toList()
      ..sort();
    return ListView(
      padding: kIsWeb
          ? const EdgeInsets.fromLTRB(28, 16, 28, 28)
          : const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.space_dashboard_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OVERVIEW · ALL BRANCHES',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1)),
                  const SizedBox(height: 3),
                  const Text('Customer follow-ups',
                      style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Customer follow-ups recycle bin',
              onPressed: () => _setRecycleBinVisible(true),
              icon: const Icon(Icons.delete_outline),
            ),
            const SizedBox(width: 6),
            Text('LIVE SYNC',
                style: TextStyle(
                    color: AppColors.successFor(Theme.of(context).brightness),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
          ]),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final metricColumns = constraints.maxWidth < 580 ? 2 : 4;
          final metricWidth =
              (constraints.maxWidth - (8 * (metricColumns - 1))) /
                  metricColumns;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
                width: metricWidth,
                child: _LeadloopMetric(
                    label: 'All customers', value: '${all.length}', tone: 0)),
            SizedBox(
                width: metricWidth,
                child: _LeadloopMetric(
                    label: 'Completed',
                    value: '${all.where((lead) => lead.isCompleted).length}',
                    tone: 1)),
            SizedBox(
                width: metricWidth,
                child: _LeadloopMetric(
                    label: 'Pending sync',
                    value: '${all.where((lead) => !lead.isSynced).length}',
                    tone: 2)),
            SizedBox(
                width: metricWidth,
                child: _LeadloopMetric(
                    label: 'Overdue',
                    value: '${overdueFollowUp2.length}',
                    tone: 3,
                    onTap: () => _showOverdueSummary(overdueFollowUp2))),
          ]);
        }),
        if (overdueFollowUp2.isNotEmpty) ...[
          const SizedBox(height: 12),
          _FollowUp2OverdueBanner(leads: overdueFollowUp2),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('FILTER CUSTOMER RECORDS',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, constraints) {
              final itemWidth = constraints.maxWidth >= 900
                  ? (constraints.maxWidth - 24) / 4
                  : (constraints.maxWidth - 8) / 2;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                SizedBox(
                  width: itemWidth,
                  child: _LeadloopDateFilter(
                    value: _dateRange,
                    onTap: _selectDateRange,
                    onClear: () => setState(() {
                      _dateRange = null;
                      _visibleRecordCount = 15;
                    }),
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _LeadloopFilter<String>(
                      label: 'Promoter',
                      value: _promoter,
                      values: promoters,
                      onChanged: (value) => setState(() {
                            _promoter = value;
                            _visibleRecordCount = 15;
                          })),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _LeadloopFilter<String>(
                      label: 'Shop',
                      value: _shop,
                      values: shops,
                      onChanged: (value) => setState(() {
                            _shop = value;
                            _visibleRecordCount = 15;
                          })),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _LeadloopFilter<LeadStatusFilter>(
                    label: 'Status',
                    value: _status,
                    values: LeadStatusFilter.values,
                    labelFor: (value) => switch (value) {
                      LeadStatusFilter.active => 'Active',
                      LeadStatusFilter.completed => 'Completed',
                    },
                    onChanged: (value) => setState(() {
                      _status = value;
                      _visibleRecordCount = 15;
                    }),
                  ),
                ),
              ]);
            }),
            const SizedBox(height: 10),
            _FollowUpStageButtons(
              selected: _stage,
              onSelected: (stage) => setState(() {
                _stage = stage;
                _visibleRecordCount = 15;
              }),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CUSTOMER RECORDS',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
                const SizedBox(height: 3),
                Text(_hasActiveFilters
                    ? '${leads.length} filtered records'
                    : '${leads.length} active records'),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: leads.isEmpty ? null : _deleteFiltered,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(
              _hasActiveFilters ? 'Move filtered to bin' : 'Move all to bin',
            ),
          ),
        ]),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, constraints) {
          final minWidth = kIsWeb && constraints.hasBoundedWidth
              ? constraints.maxWidth
              : 0.0;
          return Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minWidth),
                child: DataTable(
                  headingRowHeight: 42,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: double.infinity,
                  horizontalMargin: 16,
                  columnSpacing: 28,
                  columns: const [
                    DataColumn(label: _OwnerColumnLabel('Customer')),
                    DataColumn(label: _OwnerColumnLabel('Entered at')),
                    DataColumn(label: _OwnerColumnLabel('Comments')),
                    DataColumn(label: _OwnerColumnLabel('Shop / promoter')),
                    DataColumn(label: _OwnerColumnLabel('Follow-up')),
                    DataColumn(label: _OwnerColumnLabel('Sync')),
                    DataColumn(label: _OwnerColumnLabel('Action'))
                  ],
                  rows: visibleLeads.map((lead) {
                    final commentLayout = _commentLayout(lead);
                    return DataRow(cells: [
                      DataCell(Text('${lead.name}\n${lead.phone}')),
                      DataCell(Text(_formatDateTime(lead.createdAt))),
                      DataCell(SizedBox(
                        width: commentLayout.width,
                        height: commentLayout.height,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(commentLayout.text,
                              softWrap: false,
                              maxLines: null,
                              overflow: TextOverflow.visible),
                        ),
                      )),
                      DataCell(Text('${lead.shopName}\n${lead.promoterName}')),
                      DataCell(FollowUpDeadlineService.isOverdue(lead)
                          ? _FollowUp2OverdueCell(lead: lead)
                          : lead.isCompleted
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.successFor(
                                            Theme.of(context).brightness)
                                        .withAlpha(24),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle_outline,
                                          size: 15,
                                          color: AppColors.successFor(
                                              Theme.of(context).brightness)),
                                      const SizedBox(width: 5),
                                      Text(lead.outcomeLabel),
                                    ],
                                  ),
                                )
                              : Text('Follow-up ${lead.followUpNumber}')),
                      DataCell(Icon(
                          lead.isSynced
                              ? Icons.check_circle
                              : Icons.cloud_upload_outlined,
                          color: lead.isSynced
                              ? AppColors.successFor(
                                  Theme.of(context).brightness)
                              : AppColors.warningFor(
                                  Theme.of(context).brightness),
                          size: 18)),
                      DataCell(Wrap(children: [
                        IconButton(
                            tooltip: 'Edit customer',
                            onPressed: () => _edit(lead),
                            icon: const Icon(Icons.edit_outlined)),
                        IconButton(
                            tooltip: 'Pass to another promoter',
                            onPressed: () => _transfer(lead),
                            icon: const Icon(Icons.swap_horiz_outlined)),
                        IconButton(
                            tooltip: 'Move to recycle bin',
                            onPressed: () => _delete(lead),
                            icon: const Icon(Icons.delete_outline)),
                      ])),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          );
        }),
        if (leads.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No customers match these filters.',
                  textAlign: TextAlign.center)),
        if (visibleLeads.length < leads.length)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Center(
              child: FilledButton.tonalIcon(
                onPressed: () => setState(() => _visibleRecordCount += 15),
                icon: const Icon(Icons.expand_more),
                label: Text(
                  'Load more (${leads.length - visibleLeads.length} remaining)',
                ),
              ),
            ),
          ),
      ],
    );
  }

  _LeadCommentLayout _commentLayout(CustomerLead lead) {
    final lines = _commentLines(lead);
    final text = lines.isEmpty ? '—' : lines.join('\n');
    final cached = _commentLayouts[lead.id];
    if (cached != null && cached.text == text) return cached;

    var longestLine = 0.0;
    for (final line in lines) {
      final painter = TextPainter(
        text: TextSpan(text: line, style: const TextStyle(fontSize: 14)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (painter.width > longestLine) longestLine = painter.width;
    }
    final layout = _LeadCommentLayout(
      text: text,
      width: lines.isEmpty ? 72 : longestLine + 24,
      height: lines.isEmpty ? 24 : (lines.length * 22) + 4,
    );
    _commentLayouts[lead.id] = layout;
    return layout;
  }

  List<String> _commentLines(CustomerLead lead) {
    final comments = <String>[];
    if (lead.followUp1?.trim().isNotEmpty == true) {
      comments.add(
          'F1: ${lead.followUp1!.trim()}  ·  ${_formatDateTime(lead.followUp1At)}');
    }
    if (lead.followUp2?.trim().isNotEmpty == true) {
      comments.add(
          'F2: ${lead.followUp2!.trim()}  ·  ${_formatDateTime(lead.followUp2At)}');
    }
    if (lead.followUp3?.trim().isNotEmpty == true) {
      comments.add(
          'F3: ${lead.followUp3!.trim()}  ·  ${_formatDateTime(lead.followUp3At)}');
    }
    for (var i = 0; i < lead.additionalFollowUps.length; i++) {
      final entry = lead.additionalFollowUps[i];
      comments.add(
          'F${i + 4}: ${entry.comment}  ·  ${_formatDateTime(entry.enteredAt)}');
    }
    return comments;
  }
}

class _LeadCommentLayout {
  const _LeadCommentLayout({
    required this.text,
    required this.width,
    required this.height,
  });

  final String text;
  final double width;
  final double height;
}

class _FollowUp2OverdueBanner extends StatelessWidget {
  const _FollowUp2OverdueBanner({
    required this.leads,
    this.promoterSummary = false,
  });

  final List<CustomerLead> leads;
  final bool promoterSummary;

  @override
  Widget build(BuildContext context) {
    final isSingleLead = leads.length == 1;
    final lead = leads.first;
    final dueAt = FollowUpDeadlineService.nextDueAt(lead);
    final brightness = Theme.of(context).brightness;
    final foreground = AppColors.onErrorSurfaceFor(brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorSurfaceFor(brightness),
        border: Border.all(color: AppColors.errorFor(brightness)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(Icons.notification_important_outlined,
            size: 18, color: foreground),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            promoterSummary
                ? isSingleLead
                    ? 'You have 1 follow-up pending. Follow-up ${lead.followUpNumber + 1} for ${lead.name} was due ${_formatDateTime(dueAt)}.'
                    : 'You have ${leads.length} follow-ups pending. Review their records now.'
                : isSingleLead
                    ? 'Follow-up ${lead.followUpNumber + 1} is overdue for ${lead.name}. It was due ${_formatDateTime(dueAt)}.'
                    : 'Follow-ups are overdue for ${leads.length} customers. Review their records now.',
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ]),
    );
  }
}

class _PromoterLeadCard extends StatelessWidget {
  const _PromoterLeadCard({
    required this.lead,
    required this.onOpen,
    required this.onCall,
  });

  final CustomerLead lead;
  final VoidCallback onOpen;
  final VoidCallback onCall;

  List<String> get _comments => [
        if (lead.followUp1?.trim().isNotEmpty == true) lead.followUp1!.trim(),
        if (lead.followUp2?.trim().isNotEmpty == true) lead.followUp2!.trim(),
        if (lead.followUp3?.trim().isNotEmpty == true) lead.followUp3!.trim(),
        ...lead.additionalFollowUps
            .map((entry) => entry.comment.trim())
            .where((comment) => comment.isNotEmpty),
      ];

  _LeadStatus get _status {
    if (FollowUpDeadlineService.isOverdue(lead)) {
      return _LeadStatus.overdue;
    }
    return switch (lead.outcome) {
      EnquiryOutcome.active => _LeadStatus.active,
      EnquiryOutcome.purchased => _LeadStatus.purchased,
      EnquiryOutcome.closedWithoutPurchase => _LeadStatus.closed,
    };
  }

  String get _statusLabel => switch (_status) {
        _LeadStatus.overdue => 'Due',
        _LeadStatus.purchased => 'Purchased',
        _LeadStatus.closed => 'Closed',
        _LeadStatus.active => 'Follow-up ${lead.followUpNumber}',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final comments = _comments;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            lead.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text('|',
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                          Text(lead.phone),
                          _LeadStatusBadge(
                            label: _statusLabel,
                            status: _status,
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit customer',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onOpen,
                  ),
                  IconButton(
                    tooltip: 'Call customer',
                    icon: const Icon(Icons.phone_outlined),
                    color: AppColors.successFor(Theme.of(context).brightness),
                    onPressed: onCall,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 6),
                child: comments.isEmpty
                    ? Text(
                        'No follow-up comments yet',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var index = 0; index < comments.length; index++)
                            Padding(
                              padding: EdgeInsets.only(
                                  bottom: index == comments.length - 1 ? 0 : 5),
                              child: Text(
                                '${index + 1}. ${comments[index]}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
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

enum _LeadStatus { active, overdue, purchased, closed }

class _LeadStatusBadge extends StatelessWidget {
  const _LeadStatusBadge({required this.label, required this.status});

  final String label;
  final _LeadStatus status;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final foreground = switch (status) {
      _LeadStatus.overdue => AppColors.onErrorSurfaceFor(brightness),
      _LeadStatus.purchased => AppColors.successFor(brightness),
      _LeadStatus.active => scheme.primary,
      _LeadStatus.closed => scheme.onSurfaceVariant,
    };
    final background = switch (status) {
      _LeadStatus.overdue => AppColors.errorSurfaceFor(brightness),
      _LeadStatus.purchased => AppColors.successSurfaceFor(brightness),
      _LeadStatus.active => scheme.primaryContainer,
      _LeadStatus.closed => scheme.surfaceContainerHighest,
    };
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: foreground.withAlpha(170)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _FollowUp2OverdueCell extends StatelessWidget {
  const _FollowUp2OverdueCell({required this.lead});

  final CustomerLead lead;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dueAt = FollowUpDeadlineService.nextDueAt(lead);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('F${lead.followUpNumber + 1} overdue',
            style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
        Text('Due ${_formatDateTime(dueAt)}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
      ],
    );
  }
}

class _OwnerColumnLabel extends StatelessWidget {
  const _OwnerColumnLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(label.toUpperCase(),
      style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7));
}

class LeadloopPromoterAdminScreen extends StatefulWidget {
  const LeadloopPromoterAdminScreen({super.key, required this.backend});

  final FirebaseLeadBackend backend;

  @override
  State<LeadloopPromoterAdminScreen> createState() =>
      _LeadloopPromoterAdminScreenState();
}

class _LeadloopPromoterAdminScreenState
    extends State<LeadloopPromoterAdminScreen> {
  final WorkspaceStateStore _workspaceState = const WorkspaceStateStore();
  List<LeadloopPromoterProfile> _promoters = const [];
  bool _showRecycleBin = false;
  bool _recycleBinTouched = false;
  bool _loading = true;
  String? _error;
  bool _changing = false;

  Future<void> _moveToRecycleBin(LeadloopPromoterProfile promoter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Move promoter to recycle bin?'),
        content: Text(
            '${promoter.name} will be disabled immediately and can be restored from Recycle Bin. Customer enquiries will be kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Move to recycle bin')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _changing = true);
    try {
      await widget.backend.recyclePromoter(promoter);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Promoter moved to Recycle Bin and access was disabled.')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      const message =
          'Could not move the promoter to Recycle Bin. Check your connection and retry.';
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(message)));
      await _load();
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_restoreRecycleBin());
  }

  Future<void> _restoreRecycleBin() async {
    final visible = await _workspaceState.readPromoterRecycleBin();
    if (!mounted || _recycleBinTouched || !visible) return;
    setState(() => _showRecycleBin = true);
  }

  void _setRecycleBinVisible(bool visible) {
    _recycleBinTouched = true;
    setState(() => _showRecycleBin = visible);
    unawaited(_workspaceState.writePromoterRecycleBin(visible));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final promoters = await widget.backend.listPromoters();
      if (mounted) setState(() => _promoters = promoters);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load promoters: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(LeadloopPromoterProfile promoter) async {
    final controller = TextEditingController(text: promoter.shopName);
    final shopName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve promoter'),
        content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Assigned shop')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Approve')),
        ],
      ),
    );
    controller.dispose();
    if (shopName == null || shopName.isEmpty) return;
    await widget.backend.updatePromoter(
      uid: promoter.uid,
      shopId: _shopIdFromName(shopName),
      shopName: shopName,
      active: true,
      status: 'approved',
    );
    await _load();
  }

  Future<void> _disable(LeadloopPromoterProfile promoter) async {
    await widget.backend.updatePromoter(
      uid: promoter.uid,
      shopId: promoter.shopId,
      shopName: promoter.shopName,
      active: false,
      status: 'disabled',
    );
    await _load();
  }

  String _shopIdFromName(String shopName) => shopName
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  @override
  Widget build(BuildContext context) {
    if (_showRecycleBin) {
      return _PromoterRecycleBinView(
        backend: widget.backend,
        onBack: () => _setRecycleBinVisible(false),
      );
    }
    final pending = _promoters.where((promoter) => !promoter.active).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('OWNER ACCESS ONLY',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 11,
                      letterSpacing: 1.1)),
              const SizedBox(height: 4),
              const Text('Promoter accounts',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
            ]),
          ),
          IconButton(
              tooltip: 'Refresh promoters',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_outlined)),
          IconButton(
              tooltip: 'Promoter accounts recycle bin',
              onPressed: () => _setRecycleBinVisible(true),
              icon: const Icon(Icons.delete_outline)),
        ]),
        const SizedBox(height: 8),
        Text('$pending awaiting approval · ${_promoters.length} total',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()))
        else if (_promoters.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No promoter registrations yet.',
                      textAlign: TextAlign.center)))
        else
          ..._promoters.map((promoter) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                      child: Text(promoter.name.isEmpty
                          ? '?'
                          : promoter.name.substring(0, 1).toUpperCase())),
                  title: Text(promoter.name),
                  subtitle: Text(
                      '${promoter.mobile}\n${promoter.shopName.isEmpty ? 'No shop assigned' : promoter.shopName}'),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    enabled: !_changing,
                    tooltip: 'Manage promoter',
                    onSelected: (action) {
                      if (action == 'delete') {
                        _moveToRecycleBin(promoter);
                      } else if (action == 'disable') {
                        _disable(promoter);
                      } else {
                        _approve(promoter);
                      }
                    },
                    itemBuilder: (_) => [
                      if (promoter.status != 'deleting')
                        PopupMenuItem(
                            value: promoter.active ? 'disable' : 'approve',
                            child: Text(promoter.active
                                ? 'Disable'
                                : promoter.status == 'disabled'
                                    ? 'Reactivate'
                                    : 'Approve')),
                      const PopupMenuItem(
                          value: 'delete', child: Text('Move to recycle bin')),
                    ],
                  ),
                ),
              )),
      ],
    );
  }
}

class _PromoterRecycleBinView extends StatelessWidget {
  const _PromoterRecycleBinView({
    required this.backend,
    required this.onBack,
  });

  final FirebaseLeadBackend backend;
  final VoidCallback onBack;

  Future<void> _restore(
      BuildContext context, LeadloopPromoterProfile promoter) async {
    try {
      await backend.restorePromoter(promoter.uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${promoter.name} restored.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not restore the promoter account.')));
      }
    }
  }

  Future<void> _deleteForever(
      BuildContext context, LeadloopPromoterProfile promoter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          PromoterDeletionDialog(name: promoter.name, mobile: promoter.mobile),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable(
        'deletePromoterPermanently',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
      )
          .call({'uid': promoter.uid, 'confirmation': 'DELETE'});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${promoter.name} permanently deleted.')));
      }
    } catch (error) {
      if (!context.mounted) return;
      final message = error is FirebaseFunctionsException
          ? error.message ?? 'Permanent promoter deletion failed.'
          : 'Could not permanently delete the promoter. Retry later.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<List<LeadloopPromoterProfile>>(
        stream: backend.watchDeletedPromoters(),
        builder: (context, snapshot) {
          final promoters = snapshot.data ?? const [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              Row(children: [
                IconButton(
                    tooltip: 'Back to Promoter accounts',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Promoter accounts recycle bin',
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 8),
              const Text(
                  'Only promoter accounts are displayed here. Permanent deletion keeps customer enquiries.'),
              const SizedBox(height: 18),
              if (promoters.isEmpty)
                const Card(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child:
                            Text('No promoter accounts in this recycle bin.')))
              else
                ...promoters.map((promoter) => Card(
                      child: ListTile(
                        title: Text(promoter.name),
                        subtitle: Text(
                            '${promoter.mobile}\n${promoter.shopName.isEmpty ? 'No shop assigned' : promoter.shopName}'),
                        isThreeLine: true,
                        trailing: Wrap(children: [
                          if (promoter.status != 'deleting')
                            TextButton(
                                onPressed: () => _restore(context, promoter),
                                child: const Text('Restore')),
                          IconButton(
                              tooltip: 'Delete permanently',
                              onPressed: () =>
                                  _deleteForever(context, promoter),
                              icon: const Icon(Icons.delete_forever_outlined)),
                        ]),
                      ),
                    )),
            ],
          );
        },
      );
}

class LeadloopRecycleBinScreen extends StatefulWidget {
  const LeadloopRecycleBinScreen(
      {super.key,
      required this.store,
      required this.backend,
      required this.onBack,
      this.onChanged});

  final LocalLeadStore store;
  final FirebaseLeadBackend backend;
  final VoidCallback onBack;
  final Future<void> Function()? onChanged;

  @override
  State<LeadloopRecycleBinScreen> createState() =>
      _LeadloopRecycleBinScreenState();
}

class _LeadloopRecycleBinScreenState extends State<LeadloopRecycleBinScreen> {
  bool _deletingAll = false;
  int _visibleRecordCount = 15;

  Future<void> _restore(CustomerLead lead) async {
    try {
      await widget.store.restore(lead.id);
      await widget.onChanged?.call();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${lead.name} restored.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Restore could not sync. Please try again.'),
      ));
    }
  }

  Future<void> _deleteForever(CustomerLead lead) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete permanently?'),
        content:
            Text('${lead.name} cannot be restored after permanent deletion.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete forever')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.backend.deleteLead(lead.id);
    await widget.store.permanentlyDelete(lead.id);
    await widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  Future<void> _deleteAllForever(List<CustomerLead> deleted) async {
    if (_deletingAll || deleted.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all permanently?'),
        content: Text(
            'All ${deleted.length} records in the recycle bin will be removed from this device and Firebase. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Delete all forever'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingAll = true);
    try {
      if (!widget.backend.isConfigured) {
        throw StateError('Firebase is not configured.');
      }
      final ids = deleted.map((lead) => lead.id).toList(growable: false);
      await widget.backend.deleteLeads(ids);
      await widget.store.permanentlyDeleteMany(ids);
      await widget.onChanged?.call();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${ids.length} records permanently deleted.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Could not delete all records. Check your internet connection and try again.')));
    } finally {
      if (mounted) setState(() => _deletingAll = false);
    }
  }

  Widget _sectionTitle(String title, String emptyMessage, int count) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (count == 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(emptyMessage,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final deleted = widget.store.recycleBin();
    final visibleDeleted =
        deleted.take(_visibleRecordCount).toList(growable: false);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        Text('OWNER ACCESS ONLY',
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 11,
                letterSpacing: 1.1)),
        const SizedBox(height: 4),
        Row(children: [
          IconButton(
              tooltip: 'Back to Customer follow-ups',
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back)),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('Customer follow-ups recycle bin',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.6)),
          ),
        ]),
        const SizedBox(height: 8),
        const Text('Restore records or permanently remove them from Firebase.',
            style: TextStyle(color: Colors.grey)),
        _sectionTitle('Customer enquiries',
            'No customer enquiries in Recycle Bin.', deleted.length),
        if (deleted.isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _deletingAll ? null : () => _deleteAllForever(deleted),
              icon: _deletingAll
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_sweep_outlined),
              label: Text(_deletingAll
                  ? 'Deleting…'
                  : 'Delete all customer enquiries permanently'),
            ),
          ),
        ],
        const SizedBox(height: 22),
        if (deleted.isNotEmpty)
          ...visibleDeleted.map(
            (lead) => Card(
              child: ListTile(
                title: Text(lead.name),
                subtitle: Text(
                    '${lead.phone}\n${lead.shopName} · ${lead.promoterName}\nEntered ${_formatDateTime(lead.createdAt)}'),
                isThreeLine: true,
                trailing: Wrap(
                  children: [
                    TextButton(
                        onPressed: () => _restore(lead),
                        child: const Text('Restore')),
                    IconButton(
                      tooltip: 'Delete permanently',
                      onPressed: () => _deleteForever(lead),
                      icon: const Icon(Icons.delete_forever_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (visibleDeleted.length < deleted.length)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: FilledButton.tonalIcon(
                onPressed: () => setState(() => _visibleRecordCount += 15),
                icon: const Icon(Icons.expand_more),
                label: Text(
                  'Load more (${deleted.length - visibleDeleted.length} remaining)',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LeadloopFollowUpField extends StatelessWidget {
  const _LeadloopFollowUpField({
    required this.label,
    required this.controller,
    required this.enteredAt,
    this.enabled = true,
    this.lockedMessage,
  });

  final String label;
  final TextEditingController controller;
  final DateTime? enteredAt;
  final bool enabled;
  final String? lockedMessage;

  @override
  Widget build(BuildContext context) => TextField(
      controller: controller,
      enabled: enabled,
      minLines: 1,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Add customer response or outcome',
        helperText: !enabled
            ? lockedMessage
            : enteredAt == null
                ? 'Date and time will be saved with this comment'
                : 'Last entered ${_formatDateTime(enteredAt)}',
      ));
}

class _FollowUpStageButtons extends StatelessWidget {
  const _FollowUpStageButtons({
    required this.selected,
    required this.onSelected,
  });

  final FollowUpStage? selected;
  final ValueChanged<FollowUpStage?> onSelected;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Row(
            children: FollowUpStage.values
                .map((stage) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: stage == FollowUpStage.third ? 0 : 8,
                        ),
                        child: FilterChip(
                          label: Text(stage == FollowUpStage.later
                              ? 'Follow 4+'
                              : 'Follow ${stage.index + 1}'),
                          selected: selected == stage,
                          showCheckmark: false,
                          onSelected: (_) =>
                              onSelected(selected == stage ? null : stage),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
      );
}

class _LeadloopMetric extends StatelessWidget {
  const _LeadloopMetric({
    required this.label,
    required this.value,
    required this.tone,
    this.onTap,
  });

  final String label;
  final String value;
  final int tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = switch (tone) {
      1 => scheme.secondary,
      2 => scheme.tertiary,
      3 => scheme.error,
      _ => scheme.primary,
    };
    final cardColor = Color.alphaBlend(
      accent
          .withAlpha(Theme.of(context).brightness == Brightness.dark ? 34 : 18),
      scheme.surface,
    );
    return Material(
      color: cardColor,
      shape: RoundedRectangleBorder(
        side: BorderSide(
            color: accent.withAlpha(
                Theme.of(context).brightness == Brightness.dark ? 74 : 52)),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
          child: Row(children: [
            Container(
              width: 3,
              height: 30,
              decoration: BoxDecoration(
                  color: accent, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label.toUpperCase(),
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7)),
                    const SizedBox(height: 3),
                    Text(value,
                        style: TextStyle(
                            color: accent,
                            fontSize: 21,
                            fontWeight: FontWeight.w700)),
                  ]),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 20, color: accent),
          ]),
        ),
      ),
    );
  }
}

class _PromoterOverdueSummary {
  const _PromoterOverdueSummary({
    required this.promoterName,
    required this.shopName,
    required this.leads,
  });

  final String promoterName;
  final String shopName;
  final List<CustomerLead> leads;
}

class _LeadloopFilter<T> extends StatelessWidget {
  const _LeadloopFilter(
      {required this.label,
      required this.value,
      required this.values,
      required this.onChanged,
      this.labelFor});

  final String label;
  final T? value;
  final List<T> values;
  final ValueChanged<T?> onChanged;
  final String Function(T value)? labelFor;

  @override
  Widget build(BuildContext context) => Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T?>(
            value: value,
            isExpanded: true,
            icon: const Icon(Icons.expand_more, size: 16),
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface, fontSize: 12),
            items: [
              DropdownMenuItem<T?>(
                  value: null,
                  child: Text('Any $label',
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              ...values.map((item) => DropdownMenuItem<T?>(
                  value: item,
                  child: Text(labelFor?.call(item) ?? item.toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis))),
            ],
            onChanged: onChanged,
          ),
        ),
      );
}

class _LeadloopDateFilter extends StatelessWidget {
  const _LeadloopDateFilter({
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final DateTimeRange? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 42,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                const Icon(Icons.date_range_outlined, size: 16),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    value == null
                        ? 'Any Date'
                        : '${_formatDateOnly(value!.start)} – ${_formatDateOnly(value!.end)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (value != null)
                  InkWell(
                    onTap: onClear,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 15),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
}

String _formatDateTime(DateTime? value) {
  if (value == null) return 'Time not recorded';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${local.day.toString().padLeft(2, '0')} '
      '${months[local.month - 1]} ${local.year}, $hour:$minute $period';
}

String _formatDateOnly(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}
