// Text-grammar nagma editor (spec §3, P2). One line per vibhag, e.g.
// `S R G m | P - D P`, `-` = sustain, `,` splits a matra, `.`/`'` mark octaves.
// Validation is server-authoritative: Apply renders; a 422 shows the parser
// message inline. No grid editor in v1 — this is ~10% of the UI cost.

import 'package:flutter/material.dart';

import '../state/player_controller.dart';

class NagmaEditorScreen extends StatefulWidget {
  final PlayerController controller;

  /// When embedded in the swipeable [PlayerShell], this returns to the player
  /// page (used by the back arrow and after a successful Apply). When null (the
  /// screen is a standalone pushed route) we pop the Navigator instead.
  final VoidCallback? onClose;

  /// Reports the text field's focus state so the shell can lock page-swiping
  /// while the keyboard is up (avoids the swipe gesture fighting cursor drags).
  final ValueChanged<bool>? onFocusChanged;

  const NagmaEditorScreen({
    super.key,
    required this.controller,
    this.onClose,
    this.onFocusChanged,
  });

  @override
  State<NagmaEditorScreen> createState() => _NagmaEditorScreenState();
}

// Keep the page alive inside the PageView so an in-progress (unapplied) draft
// survives swiping to the player and back — only Apply commits it.
class _NagmaEditorScreenState extends State<NagmaEditorScreen>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.nagmaText);
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChange);
  bool _applying = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  void _onFocusChange() => widget.onFocusChanged?.call(_focus.hasFocus);

  /// Return to the player: hand back to the shell when embedded, else pop.
  void _close() {
    FocusScope.of(context).unfocus();
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
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
    if (ok) _close();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        // When embedded in the shell there is no route to pop, so provide an
        // explicit back arrow; as a pushed route, let the default one show.
        leading: widget.onClose != null
            ? IconButton(
                tooltip: 'Back to player',
                icon: const Icon(Icons.arrow_back),
                onPressed: _close,
              )
            : null,
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
              focusNode: _focus,
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
