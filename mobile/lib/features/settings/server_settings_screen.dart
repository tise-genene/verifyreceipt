import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';

class ServerSettingsScreen extends ConsumerStatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  ConsumerState<ServerSettingsScreen> createState() =>
      _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends ConsumerState<ServerSettingsScreen> {
  final _controller = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(settingsStoreProvider);
    final v = await store.getApiBaseUrl();
    if (!mounted) return;
    setState(() {
      _controller.text = v;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _normalize(String v) {
    var s = v.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Future<void> _save() async {
    final raw = _controller.text;
    final v = _normalize(raw);

    if (v.isEmpty) {
      _snack('Server URL is required.');
      return;
    }
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      _snack('Server URL must start with http:// or https://');
      return;
    }

    final store = ref.read(settingsStoreProvider);
    await store.setApiBaseUrl(v);
    if (!mounted) return;
    _snack('Saved.');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server settings'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _save,
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'API Base URL',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'https://your-backend.example.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Quick presets',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _controller.text = 'http://10.0.2.2:8080';
                        });
                      },
                      child: const Text('Android emulator (local backend)'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _controller.text = 'http://127.0.0.1:8080';
                        });
                      },
                      child: const Text('This device only (rare)'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Tip: If you\'re using a real phone and your backend is running on your PC, 10.0.2.2 will NOT work. Use your PC\'s LAN IP, e.g. http://192.168.x.x:8080, and make sure the firewall allows it.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
