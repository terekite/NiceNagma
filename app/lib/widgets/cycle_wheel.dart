// The cycle wheel: 16 matras around a ring, sam at top, a sweep hand driven by
// the audio clock. Repaints only when `position` ticks (~60 Hz) — nothing else
// in the tree rebuilds with it. This is the machine-perfect-laya invariant made
// visible: the hand hits sam exactly when the sound resolves.

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../taal.dart';
import '../services/loop_player.dart';

class CycleWheel extends StatelessWidget {
  final ValueListenable<LoopPosition> position;
  final Taal taal;
  final int avartans;

  const CycleWheel({
    super.key,
    required this.position,
    required this.taal,
    required this.avartans,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: ValueListenableBuilder<LoopPosition>(
        valueListenable: position,
        builder: (context, pos, _) {
          final phase = pos.avartanPhase(avartans, taal.matraCount);
          final matra = pos.matraIndex(avartans, taal.matraCount);
          final cycle = pos.avartanIndex(avartans);
          return CustomPaint(
            painter: _WheelPainter(
              phase: phase,
              currentMatra: matra,
              marks: taal.matraMarks,
              scheme: scheme,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${matra + 1}',
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w300,
                      color: scheme.onSurface,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'matra',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 2,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'avartan ${cycle + 1}/$avartans',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final double phase; // [0,1) through the avartan
  final int currentMatra;
  final List<Clap> marks;
  final ColorScheme scheme;

  _WheelPainter({
    required this.phase,
    required this.currentMatra,
    required this.marks,
    required this.scheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 22;
    final n = marks.length;

    // Track ring.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = scheme.outlineVariant.withValues(alpha: 0.5);
    canvas.drawCircle(center, radius, track);

    // Sweep hand — the audio clock. Sam (matra 0) is at the top (-90°).
    final angle = -math.pi / 2 + phase * 2 * math.pi;
    final hand = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
    final handPaint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = scheme.primary.withValues(alpha: 0.85);
    canvas.drawLine(center, hand, handPaint);
    canvas.drawCircle(center, 5, Paint()..color = scheme.primary);

    // Matra dots.
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + (i / n) * 2 * math.pi;
      final p = Offset(
        center.dx + radius * math.cos(a),
        center.dy + radius * math.sin(a),
      );
      final mark = marks[i];
      final isCurrent = i == currentMatra;

      final (fill, filled, baseR) = switch (mark) {
        Clap.sam => (scheme.primary, true, 9.0),
        Clap.taali => (scheme.secondary, true, 7.0),
        Clap.khaali => (scheme.error, false, 7.0),
        Clap.plain => (scheme.onSurfaceVariant, false, 5.0),
      };
      final r = isCurrent ? baseR + 4 : baseR;

      if (isCurrent) {
        canvas.drawCircle(
          p,
          r + 6,
          Paint()..color = fill.withValues(alpha: 0.22),
        );
      }
      if (filled || isCurrent) {
        canvas.drawCircle(p, r, Paint()..color = fill);
      } else {
        canvas.drawCircle(
          p,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = fill,
        );
      }

      // Matra number just outside each dot.
      final labelPos = Offset(
        center.dx + (radius + 15) * math.cos(a),
        center.dy + (radius + 15) * math.sin(a),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            fontSize: 11,
            color: isCurrent
                ? scheme.onSurface
                : scheme.onSurfaceVariant.withValues(alpha: 0.6),
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, labelPos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.phase != phase || old.currentMatra != currentMatra;
}
