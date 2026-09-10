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
import 'pin_reset_ui.dart';
import 'promoter_deletion_dialog.dart';
import 'services/export_email_service.dart';
import 'services/export_file_downloader.dart';
import 'services/firebase_export_email_service.dart';
import 'services/firebase_lead_backend.dart';
import 'services/follow_up_deadline_service.dart';
import 'services/leadloop_auth_service.dart';
import 'services/lead_export_service.dart';
import 'services/lead_search_service.dart';
import 'services/local_lead_store.dart';
import 'services/mobile_number_validator.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'theme/app_theme.dart';

enum LeadloopRole { promoter, admin }

enum LeadStatusFilter { active, completed }

class LeadloopV2 extends StatefulWidget {
  const LeadloopV2({super.key, required this.store});

  final LocalLeadStore store;

  @override
  State<LeadloopV2> createState() => _LeadloopV2State();
}

class _LeadloopV2State extends State<LeadloopV2> {
  static const _themeKey = 'enquiry_tracker_theme_mode';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  ThemeMode _themeMode = ThemeMode.light;

  bool get _isDarkMode => _themeMode == ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _restoreTheme();
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

  Future<void> _toggleTheme() async {
    final nextMode = _isDarkMode ? ThemeMode.light : ThemeMode.dark;
    setState(() => _themeMode = nextMode);
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
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Enquiry Tracker',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _themeMode,
        home: LeadloopAccessGate(
          store: widget.store,
          isDarkMode: _isDarkMode,
          onToggleTheme: _toggleTheme,
        ),
      );
}

class LeadloopAccessGate extends StatefulWidget {
  const LeadloopAccessGate({
    super.key,
    required this.store,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  final LocalLeadStore store;
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
        .snapshots(includeMetadataChanges: true)
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
    if (!RegExp(r'^\d{6,}$').hasMatch(_pinController.text)) {
      setState(() => _error = 'PIN must contain at least 6 digits.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.registerPromoter(
        name: _nameController.text,
        mobile: _mobileController.text,
        pin: _pinController.text,
        shopName: _selectedBranch,
      );
      await _auth.signOut();
      if (!mounted) return;
      setState(() {
        _registering = false;
        _error = 'Registration submitted. The owner must approve your account.';
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
    return switch (error.code) {
      'email-already-in-use' => 'This mobile number is already registered.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' =>
        'Mobile number or PIN is incorrect.',
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

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final session = _session;
    if (session != null) {
      return LeadloopShell(
        role: session.role == 'admin'
            ? LeadloopRole.admin
            : LeadloopRole.promoter,
        store: widget.store,
        session: session,
        onLogout: _logout,
        isDarkMode: widget.isDarkMode,
        onToggleTheme: widget.onToggleTheme,
      );
    }
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          child: Icon(Icons.layers_outlined,
                              color: Theme.of(context).colorScheme.onPrimary),
                        ),
                        const SizedBox(height: 20),
                        const Text('Welcome to Enquiry Tracker',
                            style: TextStyle(
                                fontSize: 26, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(
                            _registering
                                ? 'Create your promoter account.'
                                : _ownerMode
                                    ? 'Sign in with your owner account.'
                                    : 'Sign in with your mobile number and PIN.',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        const SizedBox(height: 24),
                        if (!_registering)
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
                              decoration: InputDecoration(
                                  labelText: 'Personal PIN',
                                  errorText: _error)),
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
                        ],
                        if (!_registering && _ownerMode) ...[
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
                            decoration:
                                const InputDecoration(labelText: 'Shop name'),
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
                              controller: _pinController,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Create PIN (6+ digits)')),
                          const SizedBox(height: 12),
                          TextField(
                              controller: _confirmPinController,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                  labelText: 'Confirm PIN', errorText: _error)),
                        ],
                        const SizedBox(height: 14),
                        SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                                onPressed: _busy
                                    ? null
                                    : (_registering ? _register : _submit),
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
                            (_ownerMode || _mobileController.text.isEmpty))
                          Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
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
          ),
        ],
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
  late final SyncService _syncService;
  late final FirebaseLeadBackend _firebaseBackend;
  StreamSubscription? _leadSubscription;
  bool _exporting = false;
  Timer? _deadlineRefresh;
  StreamSubscription<RemoteMessage>? _messages;

  @override
  void initState() {
    super.initState();
    _firebaseBackend = FirebaseLeadBackend();
    _syncService = SyncService();
    _syncService.start(syncPending: _syncNow);
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
      if (mounted) setState(() {});
    });
    if (_firebaseBackend.isConfigured) {
      _leadSubscription = _firebaseBackend.watchLeads(
          localStore: widget.store,
          promoterId:
              widget.role == LeadloopRole.promoter ? widget.session.uid : null,
          onChanged: () {
            if (mounted) setState(() {});
          });
    }
  }

  Future<void> _syncNow() async {
    if (!_firebaseBackend.isConfigured) return;
    try {
      if (widget.role == LeadloopRole.admin) {
        await _firebaseBackend.syncAdmin(widget.store);
      } else {
        await _firebaseBackend.syncPromoter(widget.store, widget.session.uid);
      }
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      // The local store remains usable. The next connectivity event retries.
      debugPrint('Lead sync failed: $error\n$stackTrace');
      rethrow;
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
        if (!kIsWeb) {
          final opened = await ExportEmailService.composeAndroidEmail(
            recipient: recipient!,
            subject: 'Enquiry Tracker customer follow-ups',
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
        }

        await FirebaseExportEmailService().sendExport(
          recipient: recipient!,
          fileName: fileName,
          bytes: bytes,
        );
        if (mounted) {
          _showExportMessage(
              'Excel export emailed successfully to $recipient.');
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
    if (email == null || !email.contains('@')) {
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
    _leadSubscription?.cancel();
    _deadlineRefresh?.cancel();
    _messages?.cancel();
    NotificationService.instance.stop();
    _syncService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.role == LeadloopRole.admin;
    final pages = isAdmin
        ? <Widget>[
            LeadloopAdminScreen(
                store: widget.store,
                backend: _firebaseBackend,
                onChanged: _syncService.syncNow),
            LeadloopPromoterAdminScreen(backend: _firebaseBackend),
            LeadloopRecycleBinScreen(
                store: widget.store,
                backend: _firebaseBackend,
                onChanged: _syncService.syncNow)
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
    final destinations = isAdmin
        ? const <NavigationDestination>[
            NavigationDestination(
                icon: Icon(Icons.dashboard_outlined), label: 'Admin'),
            NavigationDestination(
                icon: Icon(Icons.groups_outlined), label: 'Promoters'),
            NavigationDestination(
                icon: Icon(Icons.delete_outline), label: 'Recycle bin'),
          ]
        : const <NavigationDestination>[
            NavigationDestination(
                icon: Icon(Icons.person_outline), label: 'Promoter')
          ];
    return Scaffold(
      appBar: AppBar(title: const Text('Enquiry Tracker'), actions: [
        if (isAdmin) ...[
          IconButton(
              tooltip: 'Export to Excel',
              onPressed:
                  _exporting ? null : () => _exportCustomers(email: false),
              icon: const Icon(Icons.table_view_outlined)),
          IconButton(
              tooltip: 'Send Excel by email',
              onPressed:
                  _exporting ? null : () => _exportCustomers(email: true),
              icon: const Icon(Icons.email_outlined)),
        ],
        if (!isAdmin)
          ValueListenableBuilder<LeadloopSyncStatus>(
            valueListenable: _syncService.status,
            builder: (context, status, _) {
              final synced = status == LeadloopSyncStatus.synced;
              return Tooltip(
                message: synced ? 'Synced to Firebase' : 'Saved locally',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    synced
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    color: synced
                        ? AppColors.successFor(Theme.of(context).brightness)
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              );
            },
          ),
        if (_firebaseBackend.isConfigured)
          IconButton(
              tooltip: 'Sync now',
              onPressed: _syncNow,
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
            tooltip: 'Lock app',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.lock_outline))
      ]),
      body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
      // Flutter requires NavigationBar to have at least two destinations.
      // Promoters have one screen, so the bottom navigation is only needed
      // for the admin's Dashboard and Recycle bin tabs.
      bottomNavigationBar: destinations.length < 2
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) => setState(() => _tab = index),
              destinations: destinations),
    );
  }
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
          _FollowUp2OverdueBanner(leads: overdueFollowUp2),
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
          onChanged: (_) => setState(() {}),
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
                      setState(() {});
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
          Text('${leads.length} shown · ${allLeads.length} total',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12))
        ]),
        const SizedBox(height: 10),
        _FollowUpStageButtons(
          selected: _stage,
          onSelected: (stage) => setState(() => _stage = stage),
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
          ...leads.map((lead) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    onTap: () => _openLead(lead),
                    leading: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: Text(lead.name.substring(0, 1).toUpperCase(),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.primary))),
                    title: Text(lead.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${lead.phone} · ${lead.isCompleted ? lead.outcomeLabel : 'Follow-up ${lead.followUpNumber}'}\n${FollowUpDeadlineService.isOverdue(lead) ? 'F${lead.followUpNumber + 1} overdue · due ${_formatDateTime(FollowUpDeadlineService.nextDueAt(lead)!)}' : 'Entered ${_formatDateTime(lead.createdAt)}'}'),
                    isThreeLine: true,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          tooltip: 'Edit customer',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _openLead(lead)),
                      IconButton(
                          tooltip: 'Call customer',
                          icon: const Icon(Icons.phone_outlined),
                          color: AppColors.successFor(
                              Theme.of(context).brightness),
                          onPressed: () => _call(lead.phone)),
                    ]),
                  ),
                ),
              )),
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
  String? _shop;
  String? _promoter;
  FollowUpStage? _stage;
  DateTimeRange? _dateRange;
  LeadStatusFilter? _status;

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
      setState(() => _dateRange = selected);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move ${leads.length} filtered records?'),
        content: const Text(
            'Every record currently shown below the filters will move to the recycle bin and can be restored later.'),
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

  @override
  Widget build(BuildContext context) {
    final all = widget.store.activeLeads();
    final leads = _filterLeads(all);
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
                    tone: 3)),
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
                    onClear: () => setState(() => _dateRange = null),
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _LeadloopFilter<String>(
                      label: 'Promoter',
                      value: _promoter,
                      values: promoters,
                      onChanged: (value) => setState(() => _promoter = value)),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _LeadloopFilter<String>(
                      label: 'Shop',
                      value: _shop,
                      values: shops,
                      onChanged: (value) => setState(() => _shop = value)),
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
                    onChanged: (value) => setState(() => _status = value),
                  ),
                ),
              ]);
            }),
            const SizedBox(height: 10),
            _FollowUpStageButtons(
              selected: _stage,
              onSelected: (stage) => setState(() => _stage = stage),
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
          if (_hasActiveFilters)
            IconButton(
              tooltip: 'Move all filtered records to recycle bin',
              onPressed: leads.isEmpty ? null : _deleteFiltered,
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              ),
              icon: const Icon(Icons.delete_sweep_outlined),
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
                  rows: leads.map((lead) {
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
  const _FollowUp2OverdueBanner({required this.leads});

  final List<CustomerLead> leads;

  @override
  Widget build(BuildContext context) {
    final isSingleLead = leads.length == 1;
    final lead = leads.first;
    final dueAt = FollowUpDeadlineService.nextDueAt(lead);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(Icons.notification_important_outlined,
            size: 18, color: scheme.onErrorContainer),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            isSingleLead
                ? 'Follow-up ${lead.followUpNumber + 1} is overdue for ${lead.name}. It was due ${_formatDateTime(dueAt)}.'
                : 'Follow-ups are overdue for ${leads.length} customers. Review their records now.',
            style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
          ),
        ),
      ]),
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
  List<LeadloopPromoterProfile> _promoters = const [];
  bool _loading = true;
  String? _error;
  bool _changing = false;

  Future<void> _deletePermanently(LeadloopPromoterProfile promoter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          PromoterDeletionDialog(name: promoter.name, mobile: promoter.mobile),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _changing = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable(
        'deletePromoterPermanently',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
      )
          .call({'uid': promoter.uid, 'confirmation': 'DELETE'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Promoter permanently deleted. Customer enquiries were kept.')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      final message = error is FirebaseFunctionsException &&
              ['not-found', 'unavailable'].contains(error.code)
          ? 'Deletion service unavailable. Deploy the Firebase function first; Blaze billing is required.'
          : error is FirebaseFunctionsException
              ? error.message ?? 'Deletion failed. Retry to finish cleanup.'
              : 'Could not confirm deletion. Check your connection and retry.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      await _load();
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
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
        ]),
        const SizedBox(height: 8),
        Text('$pending awaiting approval · ${_promoters.length} total',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        const OwnerPinResetRequests(),
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
                        _deletePermanently(promoter);
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
                      PopupMenuItem(
                          value: 'delete',
                          child: Text(promoter.status == 'deleting'
                              ? 'Retry permanent deletion'
                              : 'Delete permanently')),
                    ],
                  ),
                ),
              )),
      ],
    );
  }
}

class LeadloopRecycleBinScreen extends StatefulWidget {
  const LeadloopRecycleBinScreen(
      {super.key, required this.store, required this.backend, this.onChanged});

  final LocalLeadStore store;
  final FirebaseLeadBackend backend;
  final Future<void> Function()? onChanged;

  @override
  State<LeadloopRecycleBinScreen> createState() =>
      _LeadloopRecycleBinScreenState();
}

class _LeadloopRecycleBinScreenState extends State<LeadloopRecycleBinScreen> {
  Future<void> _restore(CustomerLead lead) async {
    await widget.store.restore(lead.id);
    await widget.onChanged?.call();
    if (mounted) setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final deleted = widget.store.recycleBin();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        Text('OWNER ACCESS ONLY',
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 11,
                letterSpacing: 1.1)),
        const SizedBox(height: 4),
        const Text('Recycle bin',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.6)),
        const SizedBox(height: 8),
        Text('${deleted.length} records · retained for 30 days',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 22),
        if (deleted.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(36),
              child: Column(
                children: [
                  Icon(Icons.delete_outline, size: 34),
                  SizedBox(height: 10),
                  Text('Recycle bin is empty',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('Deleted customer records will appear here.',
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          )
        else
          ...deleted.map(
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
  });

  final String label;
  final String value;
  final int tone;

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
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(
            color: accent.withAlpha(
                Theme.of(context).brightness == Brightness.dark ? 74 : 52)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Container(
          width: 3,
          height: 30,
          decoration: BoxDecoration(
              color: accent, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  color: accent, fontSize: 21, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
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
