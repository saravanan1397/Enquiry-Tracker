import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';
import 'models/customer_lead.dart';
import 'enquiry_tracker_app.dart';
import 'services/local_lead_store.dart';
import 'services/sync_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase is optional until `flutterfire configure` is completed. This
  // fallback keeps the app usable offline while the project is being set up.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    debugPrint('Firebase is not configured yet: $error');
  }

  final store = LocalLeadStore();
  await store.open();
  runApp(EnquiryTrackerV2(store: store));
}

class EnquiryTrackerApp extends StatelessWidget {
  const EnquiryTrackerApp({super.key, required this.store});

  final LocalLeadStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Enquiry Tracker',
      theme: AppTheme.light(),
      home: AppShell(store: store),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store});

  final LocalLeadStore store;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  late final SyncService _syncService;

  @override
  void initState() {
    super.initState();
    _syncService = SyncService();
    _syncService.start(syncPending: () async {
      // Backend API sync will be connected in the next implementation slice.
    });
  }

  @override
  void dispose() {
    _syncService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            PromoterHomeScreen(store: widget.store),
            AdminDashboardScreen(store: widget.store),
            RecycleBinScreen(store: widget.store),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Promoter'),
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Admin'),
          NavigationDestination(icon: Icon(Icons.delete_outline), label: 'Recycle bin'),
        ],
      ),
    );
  }
}

class PromoterHomeScreen extends StatefulWidget {
  const PromoterHomeScreen({super.key, required this.store});

  final LocalLeadStore store;

  @override
  State<PromoterHomeScreen> createState() => _PromoterHomeScreenState();
}

class _PromoterHomeScreenState extends State<PromoterHomeScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _saveLead() async {
    if (_nameController.text.trim().isEmpty || _phoneController.text.trim().isEmpty) return;
    final lead = CustomerLead(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      shopName: 'Bengaluru Central',
      promoterName: 'Priya S.',
      createdAt: DateTime.now(),
      followUp1: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
    );
    await widget.store.save(lead);
    _nameController.clear();
    _phoneController.clear();
    _commentController.clear();
    if (mounted) setState(() {});
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final leads = widget.store.activeLeads();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      children: [
        Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: const Icon(Icons.layers_outlined, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          const Text('Enquiry Tracker', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const Spacer(),
          Icon(Icons.shield_outlined, color: Colors.grey.shade600),
        ]),
        const SizedBox(height: 30),
        Text('PROMOTER · BENGALURU CENTRAL', style: TextStyle(color: Colors.grey.shade600, fontSize: 11, letterSpacing: 1.1)),
        const SizedBox(height: 4),
        const Text('Capture a lead', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.6)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFFFF5DB), borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [Icon(Icons.cloud_off_outlined, size: 17, color: Color(0xFF9A6800)), SizedBox(width: 8), Text('Offline · Saved on this device', style: TextStyle(color: Color(0xFF9A6800), fontSize: 12))]),
        ),
        const SizedBox(height: 17),
        TextField(controller: _nameController, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Customer name')),
        const SizedBox(height: 12),
        TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number')),
        const SizedBox(height: 12),
        TextField(controller: _commentController, maxLines: 3, decoration: const InputDecoration(labelText: 'First comment', hintText: 'Optional for now')),
        const SizedBox(height: 15),
        FilledButton.icon(onPressed: _saveLead, icon: const Icon(Icons.save_outlined), label: const Text('Save customer'), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14))),
        const SizedBox(height: 28),
        Row(children: [const Text('Recent customers', style: TextStyle(fontWeight: FontWeight.w600)), const Spacer(), Text('${leads.length} saved locally', style: const TextStyle(color: Colors.grey, fontSize: 12))]),
        const SizedBox(height: 8),
        ...leads.take(5).map((lead) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(backgroundColor: const Color(0xFFEEECFF), child: Text(lead.name.substring(0, 1).toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.primary))),
              title: Text(lead.name),
              subtitle: Text(lead.phone),
              trailing: IconButton(icon: const Icon(Icons.phone_outlined), color: Colors.teal, onPressed: () => _call(lead.phone)),
            )),
      ],
    );
  }
}

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key, required this.store});

  final LocalLeadStore store;

  @override
  Widget build(BuildContext context) {
    final leads = store.activeLeads();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      children: [
        Text('ALL SHOPS · LIVE SYNC', style: TextStyle(color: Colors.grey.shade600, fontSize: 11, letterSpacing: 1.1)),
        const SizedBox(height: 4),
        const Text('Customer follow-ups', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.6)),
        const SizedBox(height: 18),
        Row(children: [
          _Metric(label: 'Customers today', value: '${leads.length}'),
          const SizedBox(width: 10),
          const _Metric(label: 'Follow-up due', value: '32'),
          const SizedBox(width: 10),
          const _Metric(label: 'Pending sync', value: '7'),
        ]),
        const SizedBox(height: 20),
        const Wrap(spacing: 8, runSpacing: 8, children: [_FilterChip(label: 'All shops'), _FilterChip(label: 'All promoters'), _FilterChip(label: 'Any follow-up')]),
        const SizedBox(height: 16),
        Card(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [DataColumn(label: Text('Customer')), DataColumn(label: Text('Shop / promoter')), DataColumn(label: Text('Follow-up')), DataColumn(label: Text('Sync'))], rows: leads.take(8).map((lead) => DataRow(cells: [DataCell(Text('${lead.name}\n${lead.phone}')), DataCell(Text('${lead.shopName}\n${lead.promoterName}')), DataCell(Text('Follow-up ${lead.currentStage.index + 1}')), DataCell(Icon(lead.isSynced ? Icons.check_circle : Icons.cloud_upload_outlined, color: lead.isSynced ? Colors.teal : Colors.orange, size: 18))])).toList()))),
        const SizedBox(height: 14),
        const Card(child: ListTile(leading: Icon(Icons.archive_outlined), title: Text('Recycle bin'), subtitle: Text('Deleted records can be restored or permanently removed by the owner.'))),
      ],
    );
  }
}

class RecycleBinScreen extends StatelessWidget {
  const RecycleBinScreen({super.key, required this.store});

  final LocalLeadStore store;

  @override
  Widget build(BuildContext context) {
    final deleted = store.recycleBin();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      children: [
        Text('OWNER ACCESS ONLY', style: TextStyle(color: Colors.grey.shade600, fontSize: 11, letterSpacing: 1.1)),
        const SizedBox(height: 4),
        const Text('Recycle bin', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.6)),
        const SizedBox(height: 8),
        Text('${deleted.length} records · retained for 30 days', style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 22),
        if (deleted.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(36),
              child: Column(
                children: [
                  Icon(Icons.delete_outline, size: 34),
                  SizedBox(height: 10),
                  Text('Recycle bin is empty', style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('Deleted customer records will appear here.', textAlign: TextAlign.center),
                ],
              ),
            ),
          )
        else
          ...deleted.map(
            (lead) => Card(
              child: ListTile(
                title: Text(lead.name),
                subtitle: Text(lead.phone),
                trailing: TextButton(onPressed: () {}, child: const Text('Restore')),
              ),
            ),
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)), const SizedBox(height: 4), Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600))]))));
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => InputChip(label: Text(label), onPressed: (