// Text-grammar nagma editor (spec §3, P2). One line per vibhag, e.g.
// `S R G m | P - D P`, `-` = sustain, `,` splits a matra, `.`/`'` mark octaves.
// Validation is server-authoritative: Apply renders; a 422 shows the parser
// message inline. No grid editor in v1 — this is ~10% of the UI cost.

import 'package:flutter/material.dart';

import '../state/player_controller.dart';

class NagmaEditorScreen extends StatefulWidget {
  final PlayerController controller;
  const NagmaEditorScreen({super.key, required this.controller});

  @override
  State<NagmaEditorScreen> createState() => _NagmaEditorScreenState();
}

class _NagmaEditorScreenState extends State<NagmaEditorScreen> {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.nagmaText);
  bool _applying = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() {
      _applying = true;
      _error = null;
    });
    final ok = await widget.controller.setNagma(_text.text);
    if (!mounted) return;
    setState(() {
      _applying = false;
      _error = ok ? null : widget.controller.nagmaError;
    });
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit lehra'),
        actions: [
          TextButton(
            onPressed: _applying ? null : _apply,
            child: _applying
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Apply'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'One line per vibhag (4 lines for Teentaal). '
              '`-` sustains, `,` splits a matra, `.` lowers / `\'` raises an octave.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                errorText: _error,
                helperText: 'Swars: S r R g G m M P d D n N',
              ),
            ),
            const SizedBox(height: 16),
            Text('Example', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(
              'S S S N.,S\ng R N. S\nM. P. g. R.,S.\ng. M. P. N.',
              style: TextStyle(
                fontFamily: 'monospace',
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
