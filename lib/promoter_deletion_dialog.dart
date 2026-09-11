import 'package:flutter/material.dart';

class PromoterDeletionDialog extends StatefulWidget {
  const PromoterDeletionDialog(
      {super.key, required this.name, required this.mobile});
  final String name;
  final String mobile;

  @override
  State<PromoterDeletionDialog> createState() => _PromoterDeletionDialogState();
}

class _PromoterDeletionDialogState extends State<PromoterDeletionDialog> {
  String _confirmation = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Delete promoter permanently?'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              '${widget.name} · ${widget.mobile}\n\nThis removes their login, profile, mobile-number reservation and notification registrations. It cannot be undone.\n\nCustomer enquiries and history are kept. Transfer open enquiries to an active promoter so follow-ups continue.\n\nTo block access temporarily, use Disable instead.'),
          const SizedBox(height: 16),
          TextField(
              onChanged: (value) => setState(() => _confirmation = value),
              decoration:
                  const InputDecoration(labelText: 'Type DELETE to confirm')),
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _confirmation == 'DELETE'
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Delete permanently')),
        ],
      );
}
