import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../reference/reference_controller.dart';

class ScanQrScreen extends ConsumerStatefulWidget {
  const ScanQrScreen({super.key});

  @override
  ConsumerState<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends ConsumerState<ScanQrScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          final barcodes = capture.barcodes;
          if (barcodes.isEmpty) return;
          final raw = barcodes.first.rawValue;
          if (raw == null || raw.trim().isEmpty) return;

          _handled = true;
          final ref = _extractRefFromQr(raw.trim());
          this.ref.read(referenceControllerProvider.notifier).setReference(ref);

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Captured: $ref')));
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _handled = false),
        icon: const Icon(Icons.refresh),
        label: const Text('Scan again'),
      ),
    );
  }

  String _extractRefFromQr(String raw) {
    try {
      final uri = Uri.tryParse(raw);
      if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
        final qp = uri.queryParameters;
        for (final key in [
          'reference',
          'ref',
          'tx',
          'transaction',
          'transactionId',
          'id',
        ]) {
          final v = qp[key];
          if (v != null && v.trim().isNotEmpty) return v.trim();
        }
        if (uri.pathSegments.isNotEmpty) return uri.pathSegments.last;
      }
    } catch (_) {}
    return raw;
  }
}
