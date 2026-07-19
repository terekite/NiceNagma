// The player screen (spec §6): cycle wheel + matra counter (audio-driven),
// tempo + Sa controls that trigger a re-render, tanpura mix, play/pause.

import 'package:flutter/material.dart';

import '../config.dart';
import '../state/player_controller.dart';
import '../widgets/cycle_wheel.dart';
import 'nagma_editor_screen.dart';

class PlayerScreen extends StatelessWidget {
  final PlayerController controller;

  /// Invoked by the top-right edit button. In the swipeable [PlayerShell] this
  /// animates the PageView to the editor page; when null (screen used as a
  /// standalone route) it falls back to pushing the editor as a MaterialPageRoute.
  final VoidCallback? onEdit;

  const PlayerScreen({super.key, required this.controller, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('NiceNagma'),
            actions: [
              IconButton(
                tooltip: 'Edit lehra',
                icon: const Icon(Icons.edit_note),
                onPressed: onEdit ??
                    () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                NagmaEditorScreen(controller: controller),
                          ),
                        ),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (!controller.serviceHealthy) _ServiceBanner(controller: controller),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            CycleWheel(
                              position: controller.position,
                              taal: controller.taal,
                              avartans: controller.avartans,
                            ),
                            if (controller.rendering)
                              const _RenderingOverlay(),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _LayaReadout(controller: controller),
                        const SizedBox(height: 16),
                        _TempoControl(controller: controller),
                        const SizedBox(height: 12),
                        _SaControl(controller: controller),
                        const SizedBox(height: 12),
                        _MixControls(controller: controller),
                      ],
                    ),
                  ),
                ),
                _TransportBar(controller: controller, scheme: scheme),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Parse free-text tempo entry into a positive BPM, or null if unusable.
/// Range-clamping is intentionally left to controller.setBpm (which clamps to
/// Config.minBpm/maxBpm), so this only rejects non-numeric / non-positive input.
double? parseTempoInput(String raw) {
  final v = double.tryParse(raw.trim());
  if (v == null || v.isNaN || v.isInfinite || v <= 0) return null;
  return v;
}

/// Prompt for an exact tempo. On Set (or keyboard submit) the parsed value goes
/// through controller.setBpm — the same path the slider uses — so the chip,
/// slider, laya label, and re-render all stay in sync. Invalid input is ignored.
Future<void> _showTempoDialog(
        BuildContext context, PlayerController controller) =>
    showDialog<void>(
      context: context,
      builder: (_) => _TempoDialog(controller: controller),
    );

/// The tempo dialog is a StatefulWidget so its TextEditingController is disposed
/// in State.dispose() — i.e. after the route (and its dismiss transition) is
/// fully gone. Disposing it synchronously after `await showDialog` instead races
/// the dialog's exit animation, which rebuilds the TextField one more frame and
/// crashes with "A TextEditingController was used after being disposed."
class _TempoDialog extends StatefulWidget {
  final PlayerController controller;
  const _TempoDialog({required this.controller});

  @override
  State<_TempoDialog> createState() => _TempoDialogState();
}

class _TempoDialogState extends State<_TempoDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.bpm.round().toString());

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _commit() {
    final v = parseTempoInput(_text.text);
    if (v != null) widget.controller.setBpm(v);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set tempo'),
      content: TextField(
        controller: _text,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _commit(),
        decoration: InputDecoration(
          suffixText: 'BPM',
          helperText: '${Config.minBpm.round()}–${Config.maxBpm.round()} BPM',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _commit, child: const Text('Set')),
      ],
    );
  }
}

class _LayaReadout extends StatelessWidget {
  final PlayerController controller;
  const _LayaReadout({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Chip(label: controller.layaLabel, color: scheme.primaryContainer),
        const SizedBox(width: 8),
        // The BPM chip is tappable: tap to type an exact tempo. Both this and the
        // slider drive controller.setBpm, so they stay in sync automatically.
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showTempoDialog(context, controller),
          child: _Chip(
              label: '${controller.bpm.round()} BPM',
              color: scheme.secondaryContainer),
        ),
        const SizedBox(width: 8),
        _Chip(label: 'Sa ${controller.sa}', color: scheme.tertiaryContainer),
        const SizedBox(width: 8),
        _Chip(label: 'Teentaal', color: scheme.surfaceContainerHighest),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

class _TempoControl extends StatelessWidget {
  final PlayerController controller;
  const _TempoControl({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tempo', style: Theme.of(context).textTheme.labelLarge),
        Slider(
          min: Config.minBpm,
          max: Config.maxBpm,
          divisions: (Config.maxBpm - Config.minBpm) ~/ 2,
          value: controller.bpm,
          label: '${controller.bpm.round()} BPM',
          onChanged: controller.setBpm,
        ),
      ],
    );
  }
}

class _SaControl extends StatelessWidget {
  final PlayerController controller;
  const _SaControl({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Sa (key)', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 16),
        Expanded(
          child: Wrap(
            spacing: 6,
            children: [
              for (final k in Config.keys)
                ChoiceChip(
                  label: Text(k),
                  selected: controller.sa == k,
                  onSelected: (_) => controller.setSa(k),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Mix section: independent Lehra and Tanpura volumes, so the user can play the
/// lehra alone, solo the tanpura drone (drop Lehra to 0), or blend the two.
class _MixControls extends StatelessWidget {
  final PlayerController controller;
  const _MixControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mix', style: Theme.of(context).textTheme.labelLarge),
        _VolumeRow(
          icon: Icons.piano,
          label: 'Lehra',
          value: controller.lehraVolume,
          onChanged: controller.setLehraVolume,
        ),
        _VolumeRow(
          icon: Icons.music_note,
          label: 'Tanpura',
          value: controller.tanpuraVolume,
          onChanged: controller.setTanpuraVolume,
        ),
      ],
    );
  }
}

class _VolumeRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _VolumeRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Slider(
            value: value,
            label: '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _TransportBar extends StatelessWidget {
  final PlayerController controller;
  final ColorScheme scheme;
  const _TransportBar({required this.controller, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Center(
        child: FilledButton.icon(
          onPressed: controller.rendering ? null : controller.togglePlay,
          icon: Icon(controller.playing ? Icons.pause : Icons.play_arrow),
          label: Text(controller.playing ? 'Pause' : 'Play'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          ),
        ),
      ),
    );
  }
}

class _RenderingOverlay extends StatelessWidget {
  const _RenderingOverlay();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            SizedBox(height: 8),
            Text('rendering…', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ServiceBanner extends StatelessWidget {
  final PlayerController controller;
  const _ServiceBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                controller.error ??
                    'Render service unreachable at ${Config.renderBaseUrl}. '
                        'Start it on the Mac and make sure the phone is on the '
                        'same Wi-Fi.',
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
              ),
            ),
            TextButton(onPressed: controller.retry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
