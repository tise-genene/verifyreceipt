import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../common/verification_result_view.dart';

class HistoryDetailScreen extends StatelessWidget {
  const HistoryDetailScreen({super.key, required this.record});

  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final provider = _providerFromValue((record['provider'] ?? '').toString());
    final ts = (record['ts'] ?? '').toString();
    final type = (record['type'] ?? '').toString();

    final result = NormalizedVerification(
      status: (record['status'] ?? 'PENDING').toString(),
      provider: (record['provider'] as String?),
      reference: (record['reference'] as String?),
      amount: (record['amount'] as num?)?.toDouble(),
      payer: record['payer'] as String?,
      date: record['date'] as String?,
      source: record['source'] as String?,
      confidence: record['confidence'] as String?,
      raw:
          (record['raw'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
    );

    return Scaffold(
      appBar: AppBar(title: const Text('History detail')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (ts.isNotEmpty || type.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (type.isNotEmpty) Text('Type: $type'),
                    if (ts.isNotEmpty) Text('Time: $ts'),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          VerificationResultView(result: result, fallbackProvider: provider),
        ],
      ),
    );
  }

  static PaymentProvider _providerFromValue(String v) {
    for (final p in PaymentProvider.values) {
      if (p.value == v) return p;
    }
    return PaymentProvider.telebirr;
  }
}
