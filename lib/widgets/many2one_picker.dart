import 'dart:async';

import 'package:flutter/material.dart';

import '../app_navigation.dart';
import '../odoo/domain.dart';
import '../odoo/rpc.dart';

/// Searchable record picker for a many2one field. Resolves to `[id, name]`
/// when a record is picked, `false` when cleared, or null when dismissed.
Future<Object?> showMany2onePicker(
  BuildContext context, {
  required OdooRpc rpc,
  required String model,
  required String title,
  required bool allowClear,
  Map<String, dynamic>? recordContext,
  List<dynamic> domain = const [],
}) {
  return showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _Many2onePicker(
      rpc: rpc,
      model: model,
      title: title,
      allowClear: allowClear,
      rpcContext: recordContext,
      domain: domain,
    ),
  );
}

class _Many2onePicker extends StatefulWidget {
  final OdooRpc rpc;
  final String model;
  final String title;
  final bool allowClear;
  final Map<String, dynamic>? rpcContext;

  /// The field's own domain (e.g. only sellable products).
  final List<dynamic> domain;

  const _Many2onePicker({
    this.domain = const [],
    required this.rpc,
    required this.model,
    required this.title,
    required this.allowClear,
    this.rpcContext,
  });

  @override
  State<_Many2onePicker> createState() => _Many2onePickerState();
}

class _Many2onePickerState extends State<_Many2onePicker> {
  List<Map<String, dynamic>>? _results;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String query) async {
    try {
      final results = await widget.rpc.searchRead(
        widget.model,
        domain: andDomains([
          widget.domain,
          if (query.isNotEmpty)
            [
              ['display_name', 'ilike', query],
            ],
        ]),
        fields: ['display_name'],
        limit: 40,
        context: widget.rpcContext,
      );
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      if (!handleRpcError(context, e)) setState(() => _results = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  if (widget.allowClear)
                    TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Clear')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search', isDense: true),
                onChanged: (q) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () => _search(q.trim()));
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: results == null
                  ? const Center(child: CircularProgressIndicator())
                  : results.isEmpty
                      ? const Center(child: Text('No matches'))
                      : ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (_, i) {
                            final r = results[i];
                            final name = r['display_name']?.toString() ?? '';
                            return ListTile(
                              title: Text(name),
                              onTap: () => Navigator.of(context).pop(<dynamic>[r['id'], name]),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
