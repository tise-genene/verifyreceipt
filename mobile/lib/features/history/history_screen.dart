import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';

final historyListProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final store = ref.watch(historyStoreProvider);
  return store.list();
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncHistory = ref.watch(historyListProvider);
    final store = ref.watch(historyStoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            onPressed: () async {
              await store.clear();
              ref.invalidate(historyListProvider);
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
          if (items.isEmpty) {
            return const Center(child: Text('No history yet'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final it = items[index];
              final status = (it['status'] ?? 'PENDING').toString();
              final provider = (it['provider'] ?? '-').toString();
              final reference = (it['reference'] ?? '-').toString();
              final ts = (it['ts'] ?? '').toString();
              return ListTile(
                title: Text('$status • $provider'),
                subtitle: Text(reference),
                trailing: Text(ts.isEmpty ? '' : ts.split('T').first),
              );
            },
          );
        },
      ),
    );
  }
}
