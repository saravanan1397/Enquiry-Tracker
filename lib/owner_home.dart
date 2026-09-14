import 'package:flutter/material.dart';

import 'models/customer_lead.dart';
import 'services/follow_up_deadline_service.dart';

class OwnerHome extends StatelessWidget {
  const OwnerHome({
    super.key,
    required this.leads,
    required this.onFollowup,
    required this.onSales,
  });

  final List<CustomerLead> leads;
  final VoidCallback onFollowup;
  final VoidCallback? onSales;

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
            actionLabel: 'Open follow-ups',
            lightAccent: const Color(0xFF0B63CE),
            darkAccent: const Color(0xFF64B5FF),
            lightGradient: const [Color(0xFFEAF3FF), Color(0xFFC9E1FF)],
            darkGradient: const [Color(0xFF07182D), Color(0xFF123B68)],
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
          _ModuleCard(
            title: 'Sales tracker',
            eyebrow: 'SALES',
            description: 'Your sales workspace',
            footer: 'Daily entries, monthly totals, Excel exports and backups',
            icon: Icons.insights_outlined,
            lightAccent: const Color(0xFFD94A16),
            darkAccent: const Color(0xFFFFA56B),
            lightGradient: const [Color(0xFFFFF0E8), Color(0xFFFFD4BF)],
            darkGradient: const [Color(0xFF251007), Color(0xFF6B2610)],
            actionLabel: onSales == null ? 'Web only' : 'Open sales tracker',
            metrics: const [('SCHEDULE', 'Daily'), ('CURRENCY', 'INR')],
            onTap: onSales,
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
    required this.actionLabel,
    required this.lightAccent,
    required this.darkAccent,
    required this.lightGradient,
    required this.darkGradient,
    required this.metrics,
    this.onTap,
  });

  final String title, eyebrow, description, footer;
  final String actionLabel;
  final IconData icon;
  final Color lightAccent, darkAccent;
  final List<Color> lightGradient, darkGradient;
  final List<(String, String)> metrics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFE9F0F1) : const Color(0xFF20383F);
    final muted = dark ? const Color(0xFF9AADB6) : const Color(0xFF586D76);
    final accent = dark ? darkAccent : lightAccent;
    final border = accent.withValues(alpha: dark ? 0.58 : 0.38);
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(22),
      color: dark ? const Color(0xFF0B141A) : const Color(0xFFF0F7F5),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: border),
          gradient: LinearGradient(colors: dark ? darkGradient : lightGradient),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 6, color: accent),
              ),
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
                          decoration: BoxDecoration(
                              color: accent, shape: BoxShape.circle),
                          child: const Icon(Icons.north_east,
                              size: 18, color: Colors.white),
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
                    LayoutBuilder(builder: (context, constraints) {
                      final action = FilledButton.icon(
                        onPressed: onTap,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              accent.withValues(alpha: 0.32),
                          disabledForegroundColor:
                              foreground.withValues(alpha: 0.72),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                        ),
                        icon: Icon(onTap == null
                            ? Icons.schedule_outlined
                            : Icons.arrow_forward_rounded),
                        label: Text(actionLabel,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      );
                      final details = Row(children: [
                        Icon(Icons.circle, size: 5, color: accent),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(footer,
                                style: TextStyle(color: muted, fontSize: 12))),
                      ]);
                      if (constraints.maxWidth < 520) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            details,
                            const SizedBox(height: 16),
                            action,
                          ],
                        );
                      }
                      return Row(children: [
                        Expanded(child: details),
                        const SizedBox(width: 16),
                        action,
                      ]);
                    }),
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
