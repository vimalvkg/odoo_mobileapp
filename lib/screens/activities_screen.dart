import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_navigation.dart';
import '../odoo/format.dart';
import '../odoo/rpc.dart';
import '../widgets/error_view.dart';
import '../widgets/skeleton.dart';
import 'record_form_screen.dart';

/// The signed-in user's activities (`mail.activity`) from every installed
/// module, grouped like Odoo's activity menu: overdue, today, upcoming.
class ActivitiesScreen extends StatefulWidget {
  final OdooRpc rpc;

  /// Reports (overdue, due today), for the home badge and summary.
  final void Function(int overdue, int today)? onDueCount;

  const ActivitiesScreen({super.key, required this.rpc, this.onDueCount});

  @override
  State<ActivitiesScreen> createState() => ActivitiesScreenState();
}

class ActivitiesScreenState extends State<ActivitiesScreen> {
  List<Map<String, dynamic>>? _activities;
  Object? _error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final rows = await widget.rpc.searchRead(
        'mail.activity',
        domain: [
          ['user_id', '=', widget.rpc.uid],
        ],
        fields: ['res_model', 'res_id', 'res_name', 'activity_type_id', 'summary', 'date_deadline', 'state'],
        order: 'date_deadline asc, id asc',
        limit: 300,
      );
      if (!mounted) return;
      setState(() {
        _activities = rows;
        _error = null;
      });
      widget.onDueCount?.call(
        rows.where((r) => r['state'] == 'overdue').length,
        rows.where((r) => r['state'] == 'today').length,
      );
    } catch (e) {
      if (!mounted) return;
      if (e is OdooException && e.isSessionExpired) {
        endSession(notice: sessionEndedNotice);
        return;
      }
      setState(() => _error = e);
    }
  }

  Future<void> _markDone(Map<String, dynamic> activity) async {
    HapticFeedback.mediumImpact();
    final id = activity['id'] as int;
    setState(() => _activities = [for (final a in _activities!) if (a['id'] != id) a]);
    try {
      await widget.rpc.callKw('mail.activity', 'action_feedback', args: [
        [id],
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Activity marked as done')));
      }
    } catch (e) {
      if (mounted) handleRpcError(context, e);
    }
    reload();
  }

  void _open(Map<String, dynamic> activity) {
    final model = activity['res_model'];
    final id = activity['res_id'];
    if (model is! String || id is! int) return;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => RecordFormScreen(
            rpc: widget.rpc,
            model: model,
            recordId: id,
            title: activity['res_name']?.toString() ?? '',
          ),
        ))
        .then((_) => reload());
  }

  static String _when(dynamic deadline) {
    final d = parseOdooDate(deadline);
    if (d == null) return '';
    final now = DateTime.now();
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    if (days == -1) return 'Yesterday';
    if (days < 0) return '${-days} days late';
    if (days < 7) return 'In $days days';
    return formatDate(d);
  }

  Widget _tile(Map<String, dynamic> a, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final type = a['activity_type_id'] is List ? (a['activity_type_id'] as List)[1].toString() : 'Activity';
    final summary = a['summary'] is String && (a['summary'] as String).isNotEmpty ? a['summary'] as String : type;
    return Dismissible(
      key: ValueKey('activity-${a['id']}'),
      direction: DismissDirection.startToEnd,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: const Color(0xFF2E9D5B).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: Color(0xFF2E9D5B)),
            SizedBox(width: 8),
            Text('Done', style: TextStyle(color: Color(0xFF2E9D5B), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        _markDone(a);
        return false;
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _open(a),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(summary, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 3),
                        Text(
                          [a['res_name']?.toString() ?? '', if (summary != type) type].where((s) => s.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _when(a['date_deadline']),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Mark as done',
                    icon: Icon(Icons.check_circle_outline, color: scheme.outline),
                    onPressed: () => _markDone(a),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activities = _activities;
    final Widget body;
    if (_error != null) {
      body = ErrorView.fromError(_error!, onRetry: () {
        setState(() => _error = null);
        reload();
      });
    } else if (activities == null) {
      body = const SkeletonCards();
    } else if (activities.isEmpty) {
      body = RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Icon(Icons.task_alt, size: 64, color: scheme.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text(
              "You're all caught up",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text('No activities assigned to you.', textAlign: TextAlign.center, style: TextStyle(color: scheme.outline)),
          ],
        ),
      );
    } else {
      const red = Color(0xFFD14343);
      const amber = Color(0xFFC77C0E);
      const green = Color(0xFF2E9D5B);
      final groups = [
        ('Overdue', red, activities.where((a) => a['state'] == 'overdue').toList()),
        ('Today', amber, activities.where((a) => a['state'] == 'today').toList()),
        ('Upcoming', green, activities.where((a) => a['state'] != 'overdue' && a['state'] != 'today').toList()),
      ];
      body = RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            for (final (label, color, items) in groups)
              if (items.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                  child: Row(
                    children: [
                      Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${items.length}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final a in items) _tile(a, color),
              ],
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('My Activities')),
      body: body,
    );
  }
}
