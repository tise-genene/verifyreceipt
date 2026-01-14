import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';

class VerificationResultView extends StatelessWidget {
  const VerificationResultView({
    super.key,
    required this.result,
    required this.fallbackProvider,
    this.onRetry,
  });

  final NormalizedVerification result;
  final PaymentProvider fallbackProvider;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final provider =
        PaymentProvider.values
            .where((p) => p.value == (result.provider ?? ''))
            .cast<PaymentProvider?>()
            .firstOrNull ??
        fallbackProvider;

    final payload = _payloadFromRaw(result.raw);
    final details = _buildDetails(provider, payload);
    final showDebug = kDebugMode;

    final failureMessage = result.status == 'SUCCESS'
        ? null
        : _friendlyFailureMessage(payload);

    final (badgeColor, badgeBg) = _statusColors(context, result.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
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
                    result.status,
                    style: TextStyle(
                      color: badgeColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.reference ?? '-',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (failureMessage != null) ...[
              Text(
                failureMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      (result.reference == null || result.reference!.isEmpty)
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: result.reference!),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Reference copied')),
                            );
                          }
                        },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy ref'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: _detailsText(
                          provider: provider,
                          result: result,
                          details: details,
                        ),
                      ),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Details copied')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_all),
                  label: const Text('Copy details'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    final summary = _detailsText(
                      provider: provider,
                      result: result,
                      details: details,
                    );
                    Share.share(summary);
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
                if (result.status != 'SUCCESS' && onRetry != null)
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (details.isNotEmpty) ...[
              const Text(
                'Details',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...details.map((e) => _kv(e.key, e.value)),
              const SizedBox(height: 8),
            ],
            if (showDebug)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Advanced: raw API response (debug)'),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      prettyJson(result.raw),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$k:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  static (Color fg, Color bg) _statusColors(
    BuildContext context,
    String status,
  ) {
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

  static Map<String, dynamic> _payloadFromRaw(Map<String, dynamic> raw) {
    final data = raw['data'];
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    return raw;
  }

  static List<MapEntry<String, String>> _buildDetails(
    PaymentProvider provider,
    Map<String, dynamic> payload,
  ) {
    final flattened = _flatten(payload);

    // Prioritized keys per provider (best UX) + keep the rest.
    final priorityKeys = switch (provider.value) {
      'telebirr' => [
        'payerName',
        'payerTelebirrNo',
        'creditedPartyName',
        'creditedPartyAccountNo',
        'transactionStatus',
        'receiptNo',
        'paymentDate',
        'settledAmount',
        'serviceFee',
        'serviceFeeVAT',
        'totalPaidAmount',
        'bankName',
      ],
      'cbe' => [
        'payer',
        'payerName',
        'receiver',
        'receiverName',
        'account',
        'receiverAccount',
        'paymentDate',
        'paymentDateTime',
        'reference',
        'referenceNo',
        'amount',
        'transferredAmount',
        'transactionStatus',
      ],
      'dashen' => [
        'payerName',
        'payer',
        'receiverName',
        'receiver',
        'transactionReference',
        'reference',
        'amount',
        'paymentDate',
        'transactionStatus',
      ],
      _ => [
        'payerName',
        'payer',
        'receiverName',
        'receiver',
        'reference',
        'amount',
        'paymentDate',
        'transactionStatus',
      ],
    };

    final out = <MapEntry<String, String>>[];

    final used = <String>{};
    for (final k in priorityKeys) {
      final v = flattened[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        if (_shouldHideDetailEntry(k, v.toString())) continue;
        used.add(k);
        out.add(MapEntry(_prettyKey(k), v.toString()));
      }
    }

    // Add the remaining fields (limited) so we still show “full info” without overwhelming.
    final remaining = flattened.entries
        .where((e) => !used.contains(e.key))
        .where((e) => e.value != null)
        .map((e) => MapEntry(_prettyKey(e.key), e.value.toString()))
        .where((e) => e.value.trim().isNotEmpty)
        .where((e) => !_shouldHideDetailEntry(e.key, e.value))
        .take(24);

    out.addAll(remaining);
    return out;
  }

  static Map<String, Object?> _flatten(Map<String, dynamic> map) {
    final out = <String, Object?>{};

    void walk(Object? value, String prefix, int depth) {
      if (depth > 3) {
        out[prefix] = value;
        return;
      }
      if (value is Map) {
        for (final entry in value.entries) {
          final k = entry.key.toString();
          walk(entry.value, prefix.isEmpty ? k : '$prefix.$k', depth + 1);
        }
        return;
      }
      if (value is List) {
        out[prefix] = value.map((e) => e.toString()).join(', ');
        return;
      }
      out[prefix] = value;
    }

    walk(map, '', 0);
    return out;
  }

  static String _prettyKey(String key) {
    return key
        .split('.')
        .map((part) {
          if (part.isEmpty) return part;
          final spaced = part.replaceAllMapped(
            RegExp(r'([a-z])([A-Z])'),
            (m) => '${m.group(1)} ${m.group(2)}',
          );
          return spaced[0].toUpperCase() + spaced.substring(1);
        })
        .join(' · ');
  }

  static String _detailsText({
    required PaymentProvider provider,
    required NormalizedVerification result,
    required List<MapEntry<String, String>> details,
  }) {
    final b = StringBuffer();
    b.writeln('VerifyReceipt result');
    b.writeln('Provider: ${provider.label}');
    b.writeln('Status: ${result.status}');
    if (result.reference != null && result.reference!.isNotEmpty) {
      b.writeln('Reference: ${result.reference}');
    }
    if (details.isNotEmpty) {
      b.writeln();
      b.writeln('Details:');
      for (final e in details.take(20)) {
        b.writeln('${e.key}: ${e.value}');
      }
    }
    return b.toString();
  }

  static bool _isMeaningful(String? v) {
    if (v == null) return false;
    final t = v.trim();
    return t.isNotEmpty && t != '-';
  }

  static bool _shouldHideDetailEntry(String key, String value) {
    final k = key.toLowerCase();
    final v = value.toLowerCase();

    // Avoid showing dev/system fields to normal users (keep them in Advanced only).
    if (k.contains('error') ||
        k.contains('stack') ||
        k.contains('trace') ||
        k == 'success' ||
        k == 'message' ||
        k == 'detail') {
      return true;
    }
    if (v.contains('puppeteer') ||
        v.contains('could not find chrome') ||
        v.contains('chrome (ver.') ||
        v.contains('chromium') ||
        v.contains('pptr.dev')) {
      return true;
    }

    // Also hide extremely long blob values in the Details section.
    if (value.length > 220) return true;
    return false;
  }

  static String _friendlyFailureMessage(Map<String, dynamic> payload) {
    final err = (payload['error'] ?? payload['message'] ?? payload['detail'])
        ?.toString()
        .trim();
    if (err != null && err.isNotEmpty) {
      final e = err.toLowerCase();
      if (e.contains('puppeteer') ||
          e.contains('could not find chrome') ||
          e.contains('chrome (ver.') ||
          e.contains('cache path') ||
          e.contains('browsers install')) {
        return 'Verification service is temporarily unavailable. Please try again in a few minutes.';
      }
      if (e.contains('not found') || e.contains('no transaction')) {
        return 'No transaction found for that reference.';
      }
      if (e.contains('invalid') || e.contains('incorrect')) {
        return 'That reference looks invalid. Please double-check and try again.';
      }
    }
    return 'Verification failed. Please try again.';
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
