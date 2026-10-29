import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_navigation.dart';
import '../l10n.dart';
import '../odoo/format.dart';
import '../odoo/rpc.dart';
import '../theme.dart';
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

  /// Today tab (overdue + due today) or Upcoming tab.
  bool _upcoming = false;

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
        fields: ['res_model', 'res_id', 'res_name', 'activity_type_id', 'summary', 'date_deadline', 'state', 'icon'],
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
    setState(
      () => _activities = [
        for (final a in _activities!)
          if (a['id'] != id) a,
      ],
    );
    try {
      await widget.rpc.callKw(
        'mail.activity',
        'action_feedback',
        args: [
          [id],
        ],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Activity marked as done'))));
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
        .push(
          MaterialPageRoute(
            builder: (_) => RecordFormScreen(
              rpc: widget.rpc,
              model: model,
              recordId: id,
              title: activity['res_name']?.toString() ?? '',
            ),
          ),
        )
        .then((_) => reload());
  }

  static String _when(dynamic deadline) {
    final d = parseOdooDate(deadline);
    if (d == null) return '';
    final now = DateTime.now();
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days == 0) return tr('Today');
    if (days == 1) return tr('Tomorrow');
    if (days == -1) return tr('Yesterday');
    if (days < 0) return tr('{n} days late', {'n': -days});
    if (days < 7) return tr('In {n} days', {'n': days});
    return formatDate(d);
  }

  /// Activity type icon, from the type's Font Awesome icon in Odoo.
  static IconData _iconOf(dynamic fa) {
    final name = fa is String ? fa : '';
    if (name.contains('phone')) return Icons.call_outlined;
    if (name.contains('envelope')) return Icons.mail_outline;
    if (name.contains('users') || name.contains('calendar')) return Icons.groups_outlined;
    if (name.contains('upload')) return Icons.upload_file_outlined;
    if (name.contains('file') || name.contains('pencil')) return Icons.description_outlined;
    return Icons.task_alt;
  }

  Widget _tile(Map<String, dynamic> a, Color accent) {
    final c = AppColors.of(context);
    final type = a['activity_type_id'] is List ? (a['activity_type_id'] as List)[1].toString() : tr('Activity');
    final summary = a['summary'] is String && (a['summary'] as String).isNotEmpty ? a['summary'] as String : type;
    const green = Color(0xFF1E7A3A);
    return Dismissible(
      key: ValueKey('activity-${a['id']}'),
      direction: DismissDirection.startToEnd,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: AlignmentDirectional.centerStart,
        decoration: BoxDecoration(color: green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(18)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, color: green),
            SizedBox(width: 8),
            Text(
              tr('Done'),
              style: TextStyle(color: green, fontWeight: FontWeight.w600),
            ),
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
            borderRadius: BorderRadius.circular(18),
            onTap: () => _open(a),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 10, 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_iconOf(a['icon']), color: accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(summary, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (summary != type) type,
                            a['res_name']?.toString() ?? '',
                          ].where((s) => s.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.muted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _when(a['date_deadline']),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent),
                        ),
                      ],
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: tr('Mark as done'),
                    style: IconButton.styleFrom(
                      side: BorderSide(color: c.border),
                      fixedSize: const Size(44, 44),
                    ),
                    icon: Icon(Icons.check, color: c.muted),
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

  Widget _segment(String label, bool selected, int count, Color badge, VoidCallback onTap) {
    final c = AppColors.of(context);
    return Expanded(
      child: Material(
        color: selected ? c.card : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: SizedBox(
            height: 38,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? c.ink : c.muted,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: badge, borderRadius: BorderRadius.circular(9)),
                    child: Text(
                      '$count',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final activities = _activities;
    const red = Color(0xFFB3261E);
    const amber = Color(0xFF9A5B00);
    final scheme = Theme.of(context).colorScheme;
    final due = activities?.where((a) => a['state'] == 'overdue' || a['state'] == 'today').length ?? 0;
    final upcoming = (activities?.length ?? 0) - due;

    final Widget body;
    if (_error != null) {
      body = ErrorView.fromError(
        _error!,
        onRetry: () {
          setState(() => _error = null);
          reload();
        },
      );
    } else if (activities == null) {
      body = const SkeletonCards();
    } else {
      final groups = _upcoming
          ? [
              (
                tr('Upcoming'),
                scheme.primary,
                activities.where((a) => a['state'] != 'overdue' && a['state'] != 'today').toList(),
              ),
            ]
          : [
              (tr('Overdue'), red, activities.where((a) => a['state'] == 'overdue').toList()),
              (tr('Today'), amber, activities.where((a) => a['state'] == 'today').toList()),
            ];
      final empty = groups.every((g) => g.$3.isEmpty);
      body = RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (empty) ...[
              const SizedBox(height: 80),
              Icon(Icons.task_alt, size: 64, color: scheme.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                _upcoming ? tr('Nothing planned') : tr("You're all caught up"),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                _upcoming ? tr('No upcoming activities.') : tr('Nothing overdue or due today.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted),
              ),
            ],
            for (final (label, color, items) in groups)
              if (items.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                  child: Text(
                    label.toUpperCase(),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: color),
                  ),
                ),
                for (final a in items) _tile(a, color),
              ],
            if (!empty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  tr('Swipe to mark done · tap to open the record'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Text(
                tr('My activities'),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    _segment(tr('Today'), !_upcoming, due, red, () => setState(() => _upcoming = false)),
                    _segment(tr('Upcoming'), _upcoming, upcoming, scheme.primary, () => setState(() => _upcoming = true)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
