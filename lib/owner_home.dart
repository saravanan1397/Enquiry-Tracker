import 'package:flutter/material.dart';

import 'models/customer_lead.dart';
import 'services/follow_up_deadline_service.dart';

class OwnerHome extends StatelessWidget {
  const OwnerHome({super.key, required this.leads, required this.onFollowup});

  final List<CustomerLead> leads;
  final VoidCallback onFollowup;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _ModuleCard(
            title: 'Followup widget',
            eyebrow: 'CUSTOMER ENQUIRIES',
            description: 'Customer follow-ups at a glance',
            footer: 'Open records, filters, exports and follow-up management',
            icon: Icons.forum_outlined,
            onTap: onFollowup,
            metrics: [
              ('TOTAL ENQUIRIES', '${leads.length}'),
              ('ACTIVE', '${leads.where((lead) => !lead.isCompleted).length}'),
              (
                'COMPLETED',
                '${leads.where((lead) => lead.isCompleted).length}'
              ),
              (
                'OVERDUE',
                '${leads.where((lead) => FollowUpDeadlineService.isOverdue(lead)).length}'
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _ModuleCard(
            title: 'Sales tracker',
            eyebrow: 'SALES',
            description: 'Your sales workspace',
            footer: 'Sales tracking features will be added here',
            icon: Icons.insights_outlined,
            metrics: [('STATUS', 'Coming soon')],
          ),
        ],
      );
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.title,
    required this.eyebrow,
    required this.description,
    required this.footer,
    required this.icon,
    required this.metrics,
    this.onTap,
  });

  final String title, eyebrow, description, footer;
  final IconData icon;
  final List<(String, String)> metrics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFE9F0F1) : const Color(0xFF20383F);
    final muted = dark ? const Color(0xFF9AADB6) : const Color(0xFF586D76);
    final accent = dark ? const Color(0xFF85DCC0) : const Color(0xFF216B58);
    final border = dark ? const Color(0xFF2B3D43) : const Color(0xFFCADAD9);
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(22),
      color: dark ? const Color(0xFF0B141A) : const Color(0xFFF0F7F5),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: border),
          gradient: LinearGradient(
            colors: dark
                ? const [Color(0xFF080E14), Color(0xFF152C32)]
                : const [Color(0xFFF8FAFA), Color(0xFFDFEEEA)],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(
                right: -12,
                top: 28,
                child: Transform.rotate(
                  angle: -0.22,
                  child: Icon(icon,
                      size: 220, color: accent.withValues(alpha: 0.07)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(eyebrow,
                              style: TextStyle(
                                  color: muted,
                                  fontSize: 11,
                                  letterSpacing: 1.1))),
                      if (onTap != null)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                              color: Color(0xFFE7BD73), shape: BoxShape.circle),
                          child: const Icon(Icons.north_east,
                              size: 18, color: Color(0xFF3D301B)),
                        )
                      else
                        Icon(Icons.insights_outlined, color: muted, size: 24),
                    ]),
                    const SizedBox(height: 20),
                    Text(title,
                        style: TextStyle(
                            color: foreground,
                            fontSize: 24,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(description,
                        style: TextStyle(color: muted, fontSize: 13)),
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        color: (dark ? Colors.black : Colors.white)
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      child: LayoutBuilder(builder: (context, constraints) {
                        final columns = metrics.length == 1
                            ? 1
                            : constraints.maxWidth < 560
                                ? 2
                                : 4;
                        return Wrap(children: [
                          for (var index = 0; index < metrics.length; index++)
                            SizedBox(
                              width: constraints.maxWidth / columns,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                    border: Border(
                                  left: index % columns == 0
                                      ? BorderSide.none
                                      : BorderSide(color: border),
                                  top: index < columns
                                      ? BorderSide.none
                                      : BorderSide(color: border),
                                )),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(metrics[index].$1,
                                          style: TextStyle(
                                              color: muted,
                                              fontSize: 10,
                                              letterSpacing: 0.4)),
                                      const SizedBox(height: 8),
                                      Text(metrics[index].$2,
                                          style: TextStyle(
                                              color: accent,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 18)),
                                    ]),
                              ),
                            ),
                        ]);
                      }),
                    ),
                    const SizedBox(height: 24),
                    Row(children: [
                      Icon(Icons.circle, size: 5, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(footer,
                              style: TextStyle(color: muted, fontSize: 12))),
                    ]),
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
