import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/customer_lead.dart';
import 'services/firebase_lead_backend.dart';
import 'services/leadloop_auth_service.dart';
import 'services/lead_export_service.dart';
import 'services/local_lead_store.dart';
import 'services/sync_service.dart';
import 'theme/app_theme.dart';

enum LeadloopRole { promoter, admin }

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
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _shopController = TextEditingController(text: 'Bengaluru Central');
  LeadloopAuthSession? _session;
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
    _nameController.dispose();
    _mobileController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _shopController.dispose();
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
        shopName: _shopController.text,
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

  void _logout() {
    _authService?.signOut();
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
                              decoration: const InputDecoration(
                                  labelText: 'Mobile number')),
                          const SizedBox(height: 12),
                          TextField(
                              controller: _shopController,
                              decoration: const InputDecoration(
                                  labelText: 'Shop name')),
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

  @override
  void initState() {
    super.initState();
    _firebaseBackend = FirebaseLeadBackend();
    _syncService = SyncService();
    _syncService.start(syncPending: _syncNow);
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
    } catch (error) {
      // The local store remains usable. The next connectivity event retries.
      debugPrint('Lead sync failed: $error');
    }
  }

  Future<void> _exportCustomers({required bool email}) async {
    await _syncService.syncNow();
    if (!mounted) return;

    String? recipient;
    if (email) {
      recipient = await _askForEmail();
      if (recipient == null) return;
    }

    final bytes = LeadExportService().buildWorkbook(
      activeLeads: widget.store.activeLeads(),
      deletedLeads: widget.store.recycleBin(),
    );
    final fileName =
        'enquiry_tracker_customers_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    await SharePlus.instance.share(
      ShareParams(
        title: email ? 'Email customer export' : 'Export customer data',
        subject: 'Enquiry Tracker customer follow-ups',
        text: email
            ? 'Please send this Enquiry Tracker export to $recipient.'
            : 'Enquiry Tracker customer follow-up export',
        files: [
          XFile.fromData(
            bytes,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        fileNameOverrides: [fileName],
      ),
    );
  }

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
            ValueListenableBuilder<LeadloopSyncStatus>(
                valueListenable: _syncService.status,
                builder: (context, syncStatus, _) => LeadloopPromoterScreen(
                    store: widget.store,
                    onChanged: _syncService.syncNow,
                    syncStatus: syncStatus,
                    promoterId: widget.session.uid,
                    promoterName: widget.session.displayName,
                    shopId: widget.session.shopId,
                    shopName: widget.session.shopName))
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
              onPressed: () => _exportCustomers(email: false),
              icon: const Icon(Icons.table_view_outlined)),
          IconButton(
              tooltip: 'Send Excel by email',
              onPressed: () => _exportCustomers(email: true),
              icon: const Icon(Icons.email_outlined)),
        ],
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
      required this.syncStatus,
      this.onChanged});

  final LocalLeadStore store;
  final String promoterId;
  final String promoterName;
  final String shopId;
  final String shopName;
  final LeadloopSyncStatus syncStatus;
  final Future<void> Function()? onChanged;

  @override
  State<LeadloopPromoterScreen> createState() => _LeadloopPromoterScreenState();
}

class _LeadloopPromoterScreenState extends State<LeadloopPromoterScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _comment = TextEditingController();
  FollowUpStage? _stage;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _comment.dispose();
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Customer saved locally.')));
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

  Widget _syncBanner(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (message, color, icon) = switch (widget.syncStatus) {
      LeadloopSyncStatus.checking => (
          'Checking internet connection...',
          isDark ? AppColors.darkPrimarySurface : AppColors.primaryContainer,
          Icons.sync
        ),
      LeadloopSyncStatus.offline => (
          'Offline · Saved on this device',
          isDark ? AppColors.darkWarningSurface : AppColors.warningSurface,
          Icons.cloud_off_outlined
        ),
      LeadloopSyncStatus.syncing => (
          'Syncing with Firebase...',
          isDark ? AppColors.darkPrimarySurface : AppColors.primaryContainer,
          Icons.sync
        ),
      LeadloopSyncStatus.synced => (
          'Online · Synced to Firebase',
          isDark ? AppColors.darkSuccessSurface : AppColors.successSurface,
          Icons.cloud_done_outlined
        ),
      LeadloopSyncStatus.error => (
          'Sync failed · Saved locally; will retry',
          isDark ? AppColors.darkErrorSurface : AppColors.errorSurface,
          Icons.cloud_off_outlined
        ),
    };
    final foreground = widget.syncStatus == LeadloopSyncStatus.offline
        ? (isDark ? AppColors.darkWarning : AppColors.warning)
        : widget.syncStatus == LeadloopSyncStatus.error
            ? (isDark ? AppColors.darkError : AppColors.error)
            : widget.syncStatus == LeadloopSyncStatus.synced
                ? (isDark ? AppColors.darkSuccess : AppColors.success)
                : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, size: 17, color: foreground),
        const SizedBox(width: 8),
        Text(message, style: TextStyle(color: foreground, fontSize: 12))
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The local Hive box can contain records from previous sessions on a
    // shared device. Promoters must only see records created by their UID.
    final allLeads = widget.store
        .activeLeads()
        .where((lead) => lead.promoterId == widget.promoterId)
        .toList();
    final leads = allLeads
        .where((lead) => _stage == null || lead.currentStage == _stage)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        Text('PROMOTER · ${widget.shopName.toUpperCase()}',
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 11,
                letterSpacing: 1.1)),
        const SizedBox(height: 4),
        const Text('Capture a lead',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.6)),
        const SizedBox(height: 12),
        _syncBanner(context),
        const SizedBox(height: 17),
        TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Customer name')),
        const SizedBox(height: 12),
        TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
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
        const SizedBox(height: 28),
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
          ...leads.map((lead) => ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => _openLead(lead),
                leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text(lead.name.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary))),
                title: Text(lead.name),
                subtitle: Text(
                    '${lead.phone} · Follow-up ${lead.currentStage.index + 1}\nEntered ${_formatDateTime(lead.createdAt)}'),
                isThreeLine: true,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      tooltip: 'Edit customer',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _openLead(lead)),
                  IconButton(
                      tooltip: 'Call customer',
                      icon: const Icon(Icons.phone_outlined),
                      color: AppColors.successFor(Theme.of(context).brightness),
                      onPressed: () => _call(lead.phone)),
                ]),
              )),
      ],
    );
  }
}

class LeadloopFollowUpScreen extends StatefulWidget {
  const LeadloopFollowUpScreen(
      {super.key, required this.store, required this.lead, this.onChanged});

  final LocalLeadStore store;
  final CustomerLead lead;
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

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.lead.name);
    _phone = TextEditingController(text: widget.lead.phone);
    _first = TextEditingController(text: widget.lead.followUp1 ?? '');
    _second = TextEditingController(text: widget.lead.followUp2 ?? '');
    _third = TextEditingController(text: widget.lead.followUp3 ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _first.dispose();
    _second.dispose();
    _third.dispose();
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
    final savedAt = DateTime.now();
    final first = _first.text.trim();
    final second = _second.text.trim();
    final third = _third.text.trim();
    await widget.store.save(widget.lead.copyWith(
      name: name,
      phone: phone,
      followUp1: first,
      followUp1At: _commentTime(
          widget.lead.followUp1, first, widget.lead.followUp1At, savedAt),
      followUp2: second,
      followUp2At: _commentTime(
          widget.lead.followUp2, second, widget.lead.followUp2At, savedAt),
      followUp3: third,
      followUp3At: _commentTime(
          widget.lead.followUp3, third, widget.lead.followUp3At, savedAt),
      isSynced: false,
    ));
    await widget.onChanged?.call();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit customer')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const Text('Customer details',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
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
              decoration: const InputDecoration(labelText: 'Mobile number'),
            ),
            const SizedBox(height: 8),
            Text('Entered ${_formatDateTime(widget.lead.createdAt)}',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12)),
            const SizedBox(height: 22),
            _LeadloopFollowUpField(
              label: 'Follow-up 1',
              controller: _first,
              enteredAt: widget.lead.followUp1At,
            ),
            const SizedBox(height: 14),
            _LeadloopFollowUpField(
              label: 'Follow-up 2',
              controller: _second,
              enteredAt: widget.lead.followUp2At,
            ),
            const SizedBox(height: 14),
            _LeadloopFollowUpField(
              label: 'Follow-up 3',
              controller: _third,
              enteredAt: widget.lead.followUp3At,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: const Text('Save follow-ups'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14))),
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
  String? _shop;
  String? _promoter;
  FollowUpStage? _stage;

  List<CustomerLead> get _filtered => widget.store
      .activeLeads()
      .where((lead) =>
          (_shop == null || lead.shopName == _shop) &&
          (_promoter == null || lead.promoterName == _promoter) &&
          (_stage == null || lead.currentStage == _stage))
      .toList();

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
    final leads = _filtered;
    final shops = all.map((lead) => lead.shopName).toSet().toList()..sort();
    final promoters = all.map((lead) => lead.promoterName).toSet().toList()
      ..sort();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        Text('ALL SHOPS · LIVE SYNC',
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 11,
                letterSpacing: 1.1)),
        const SizedBox(height: 4),
        const Text('Customer follow-ups',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.6)),
        const SizedBox(height: 18),
        Row(children: [
          _LeadloopMetric(
              label: 'Customers today', value: '${all.length}', tone: 0),
          const SizedBox(width: 10),
          _LeadloopMetric(
              label: 'Follow-up 3',
              value:
                  '${all.where((lead) => lead.currentStage == FollowUpStage.third).length}',
              tone: 1),
          const SizedBox(width: 10),
          _LeadloopMetric(
              label: 'Pending sync',
              value: '${all.where((lead) => !lead.isSynced).length}',
              tone: 2),
        ]),
        const SizedBox(height: 20),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
              child: _LeadloopFilter<String>(
                  label: 'Shop',
                  value: _shop,
                  values: shops,
                  onChanged: (value) => setState(() => _shop = value))),
          const SizedBox(width: 6),
          Expanded(
              child: _LeadloopFilter<String>(
                  label: 'Promoter',
                  value: _promoter,
                  values: promoters,
                  onChanged: (value) => setState(() => _promoter = value))),
        ]),
        const SizedBox(height: 10),
        _FollowUpStageButtons(
          selected: _stage,
          onSelected: (stage) => setState(() => _stage = stage),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final minWidth = kIsWeb && constraints.hasBoundedWidth
              ? constraints.maxWidth
              : 0.0;
          return Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minWidth),
                child: DataTable(
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 180,
                  columns: const [
                    DataColumn(label: Text('Customer')),
                    DataColumn(label: Text('Entered at')),
                    DataColumn(label: Text('Comments')),
                    DataColumn(label: Text('Shop / promoter')),
                    DataColumn(label: Text('Follow-up')),
                    DataColumn(label: Text('Sync')),
                    DataColumn(label: Text('Action'))
                  ],
                  rows: leads
                      .map((lead) => DataRow(cells: [
                            DataCell(Text('${lead.name}\n${lead.phone}')),
                            DataCell(Text(_formatDateTime(lead.createdAt))),
                            DataCell(SizedBox(
                              width: _commentWidth(lead),
                              height: _commentHeight(lead),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(_commentsFor(lead),
                                    softWrap: false,
                                    maxLines: 3,
                                    overflow: TextOverflow.visible),
                              ),
                            )),
                            DataCell(
                                Text('${lead.shopName}\n${lead.promoterName}')),
                            DataCell(Text(
                                'Follow-up ${lead.currentStage.index + 1}')),
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
                          ]))
                      .toList(),
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

  String _commentsFor(CustomerLead lead) {
    final comments = _commentLines(lead);
    return comments.isEmpty ? '—' : comments.join('\n');
  }

  double _commentWidth(CustomerLead lead) {
    final lines = _commentLines(lead);
    if (lines.isEmpty) return 72;

    var longestLine = 0.0;
    for (final line in lines) {
      final painter = TextPainter(
        text: TextSpan(text: line, style: const TextStyle(fontSize: 14)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (painter.width > longestLine) longestLine = painter.width;
    }
    return longestLine + 24;
  }

  double _commentHeight(CustomerLead lead) {
    final lineCount = _commentLines(lead).length;
    return lineCount == 0 ? 24 : (lineCount * 22) + 4;
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
    return comments;
  }
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
                  trailing: promoter.active
                      ? OutlinedButton(
                          onPressed: () => _disable(promoter),
                          child: const Text('Disable'))
                      : FilledButton(
                          onPressed: () => _approve(promoter),
                          child: const Text('Approve')),
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
  });

  final String label;
  final TextEditingController controller;
  final DateTime? enteredAt;

  @override
  Widget build(BuildContext context) => TextField(
      controller: controller,
      minLines: 1,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Add customer response or outcome',
        helperText: enteredAt == null
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
                          label: Text('Follow ${stage.index + 1}'),
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
      _ => scheme.primary,
    };
    final cardColor = Color.alphaBlend(
      accent
          .withAlpha(Theme.of(context).brightness == Brightness.dark ? 34 : 18),
      scheme.surface,
    );
    return Expanded(
      child: Card(
          color: cardColor,
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(value,
                        style: TextStyle(
                            color: accent,
                            fontSize: 23,
                            fontWeight: FontWeight.w700))
                  ]))),
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
