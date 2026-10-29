import 'dart:math';

import 'package:flutter/material.dart';

/// A circular progress ring.
class RingPainter extends CustomPainter {
  RingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.13;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, 0, 2 * pi, false, paint);
    final sweep = 2 * pi * progress.clamp(0.0, 1.0).toDouble();
    if (sweep > 0) {
      paint.color = color;
      canvas.drawArc(rect, -pi / 2, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

/// Cumulative chunks read per day, against the straight line to the goal.
class PaceChartPainter extends CustomPainter {
  PaceChartPainter({
    required this.actual,
    required this.total,
    required this.goalDays,
    required this.actualColor,
    required this.goalColor,
    required this.axisColor,
  });

  final List<int> actual;
  final int total;
  final int? goalDays;
  final Color actualColor;
  final Color goalColor;
  final Color axisColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (actual.isEmpty) return;
    const pad = 6.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    final days = max(max(actual.length, goalDays ?? 0), 2);
    double x(int i) => pad + w * i / (days - 1);
    double y(num v) => pad + h * (1 - v / max(total, 1));

    canvas.drawLine(
      Offset(pad, y(0)),
      Offset(size.width - pad, y(0)),
      Paint()
        ..color = axisColor
        ..strokeWidth = 1,
    );

    if (goalDays != null) {
      canvas.drawLine(
        Offset(x(0), y(0)),
        Offset(x(goalDays! - 1), y(total)),
        Paint()
          ..color = goalColor
          ..strokeWidth = 2,
      );
    }

    final path = Path()..moveTo(x(0), y(actual.first));
    for (var i = 1; i < actual.length; i++) {
      path.lineTo(x(i), y(actual[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = actualColor,
    );
  }

  @override
  bool shouldRepaint(PaceChartPainter old) =>
      old.actual != actual ||
      old.total != total ||
      old.goalDays != goalDays ||
      old.actualColor != actualColor ||
      old.goalColor != goalColor ||
      old.axisColor != axisColor;
}
