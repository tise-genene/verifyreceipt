import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../settings/server_settings_screen.dart';
import 'history_detail_screen.dart';

final historyListProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final store = ref.watch(historyStoreProvider);
  return store.list();
});

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final TextEditingController _queryController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _queryController.addListener(() {
      setState(() {
        _query = _queryController.text;
      });
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncHistory = ref.watch(historyListProvider);
    final store = ref.watch(historyStoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ServerSettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Server settings',
          ),
          IconButton(
            onPressed: () async {
              await store.clear();
              ref.invalidate(historyListProvider);
              _queryController.clear();
            },
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
          ),
        ],
      ),
      body: asyncHistory.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (items) {
          final q = _query.trim().toLowerCase();
          final filtered = q.isEmpty
              ? items
              : items.where((it) {
                  final provider = (it['provider'] ?? '')
                      .toString()
                      .toLowerCase();
                  final status = (it['status'] ?? '').toString().toLowerCase();
                  final reference = (it['reference'] ?? '')
                      .toString()
                      .toLowerCase();
                  final type = (it['type'] ?? '').toString().toLowerCase();
                  return provider.contains(q) ||
                      status.contains(q) ||
                      reference.contains(q) ||
                      type.contains(q);
                }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _queryController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search reference, provider, status…',
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () => _queryController.clear(),
                            icon: const Icon(Icons.close),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No matching history'))
                    : ListView.separated(
                        itemCount: filtered.length,
                    separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final it = filtered[index];
                          final status = (it['status'] ?? 'PENDING').toString();
                          final provider = (it['provider'] ?? '-').toString();
                          final reference = (it['reference'] ?? '-').toString();
                          final ts = (it['ts'] ?? '').toString();
                          final (badgeColor, badgeBg) = _statusColors(
                            context,
                            status,
                          );

                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: badgeColor),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  color: badgeColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(provider),
                            subtitle: Text(reference),
                            trailing: Text(_formatTs(ts)),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      HistoryDetailScreen(record: it),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

(Color fg, Color bg) _statusColors(BuildContext context, String status) {
  final cs = Theme.of(context).colorScheme;
  switch (status) {
    case 'SUCCESS':
      return (Colors.green, Colors.green.withValues(alpha: 0.12));
    case 'FAILED':
      return (cs.error, cs.error.withValues(alpha: 0.12));
    default:
      return (Colors.orange, Colors.orange.withValues(alpha: 0.12));
  }
}

String _formatTs(String ts) {
  if (ts.isEmpty) return '';
  try {
    final d = DateTime.parse(ts).toLocal();
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  } catch (_) {
    return ts.split('T').first;
  }
}
