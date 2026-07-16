// lib/widgets/support_illustration.dart
//
// A warm, original illustration for the HomeScreen showing two people
// reaching toward each other — symbolizing connection and support.
// Drawn with CustomPainter, no external image assets needed.

import 'package:flutter/material.dart';
import 'dart:math' as math;

class SupportIllustration extends StatelessWidget {
  final double width;
  final double height;

  const SupportIllustration({
    super.key,
    this.width = 280,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SupportIllustrationPainter(),
      ),
    );
  }
}

class _SupportIllustrationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Soft ground/base shadow ──
    final groundPaint = Paint()..color = Colors.white.withOpacity(0.12);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.92), width: w * 0.85, height: h * 0.10),
      groundPaint,
    );

    // ── Person 1 (left, lighter tone) ──
    _drawPerson(
      canvas,
      baseX: w * 0.30,
      baseY: h * 0.88,
      scale: h / 200,
      skinColor: const Color(0xFFFFD7B5),
      shirtColor: Colors.white.withOpacity(0.92),
      hairColor: const Color(0xFF4A3728),
      facingRight: true,
      armRaised: true,
    );

    // ── Person 2 (right, warmer tone) ──
    _drawPerson(
      canvas,
      baseX: w * 0.70,
      baseY: h * 0.88,
      scale: h / 200,
      skinColor: const Color(0xFFB07A56),
      shirtColor: const Color(0xFF3DBCB8),
      hairColor: const Color(0xFF1E1E1E),
      facingRight: false,
      armRaised: true,
    );

    // ── Small connecting hearts/sparkle between hands ──
    final sparkPaint = Paint()..color = Colors.white.withOpacity(0.85);
    final midX = w * 0.5;
    final midY = h * 0.42;
    _drawSparkle(canvas, Offset(midX, midY), 6 * (h / 200), sparkPaint);
    _drawSparkle(canvas, Offset(midX - 14 * (h / 200), midY + 10 * (h / 200)), 3.5 * (h / 200), sparkPaint);
    _drawSparkle(canvas, Offset(midX + 16 * (h / 200), midY + 6 * (h / 200)), 4 * (h / 200), sparkPaint);
  }

  void _drawPerson(
    Canvas canvas, {
    required double baseX,
    required double baseY,
    required double scale,
    required Color skinColor,
    required Color shirtColor,
    required Color hairColor,
    required bool facingRight,
    required bool armRaised,
  }) {
    final dir = facingRight ? 1.0 : -1.0;

    final skinPaint = Paint()..color = skinColor;
    final shirtPaint = Paint()..color = shirtColor;
    final hairPaint = Paint()..color = hairColor;
    final pantsPaint = Paint()..color = Colors.black.withOpacity(0.25);

    // Legs
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(baseX - 14 * scale, baseY - 50 * scale, 12 * scale, 50 * scale),
        Radius.circular(6 * scale),
      ),
      pantsPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(baseX + 2 * scale, baseY - 50 * scale, 12 * scale, 50 * scale),
        Radius.circular(6 * scale),
      ),
      pantsPaint,
    );

    // Body (shirt) — rounded rect torso
    final torsoRect = Rect.fromLTWH(baseX - 22 * scale, baseY - 100 * scale, 44 * scale, 55 * scale);
    canvas.drawRRect(RRect.fromRectAndRadius(torsoRect, Radius.circular(18 * scale)), shirtPaint);

    // Raised arm reaching toward center
    if (armRaised) {
      final armPath = Path();
      final shoulderX = baseX + dir * 16 * scale;
      final shoulderY = baseY - 92 * scale;
      armPath.moveTo(shoulderX, shoulderY);
      armPath.quadraticBezierTo(
        shoulderX + dir * 30 * scale, shoulderY - 18 * scale,
        shoulderX + dir * 46 * scale, shoulderY - 8 * scale,
      );
      canvas.drawPath(
        armPath,
        Paint()
          ..color = skinColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 11 * scale
          ..strokeCap = StrokeCap.round,
      );
      // Hand
      canvas.drawCircle(Offset(shoulderX + dir * 46 * scale, shoulderY - 8 * scale), 6.5 * scale, skinPaint);
    }

    // Other arm resting at side
    final restArmX = baseX - dir * 18 * scale;
    canvas.drawLine(
      Offset(restArmX, baseY - 90 * scale),
      Offset(restArmX - dir * 4 * scale, baseY - 60 * scale),
      Paint()
        ..color = skinColor
        ..strokeWidth = 10 * scale
        ..strokeCap = StrokeCap.round,
    );

    // Head
    final headCenter = Offset(baseX, baseY - 118 * scale);
    canvas.drawCircle(headCenter, 17 * scale, skinPaint);

    // Hair (simple cap shape)
    final hairPath = Path();
    hairPath.addArc(
      Rect.fromCircle(center: headCenter, radius: 17 * scale),
      math.pi,
      math.pi,
    );
    hairPath.close();
    canvas.drawPath(hairPath, hairPaint);

    // Simple smile
    canvas.drawArc(
      Rect.fromCenter(center: Offset(headCenter.dx, headCenter.dy + 4 * scale), width: 14 * scale, height: 10 * scale),
      0.2, 2.7,
      false,
      Paint()
        ..color = Colors.black.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * scale
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawSparkle(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    path.moveTo(center.dx, center.dy - size);
    path.lineTo(center.dx + size * 0.3, center.dy - size * 0.3);
    path.lineTo(center.dx + size, center.dy);
    path.lineTo(center.dx + size * 0.3, center.dy + size * 0.3);
    path.lineTo(center.dx, center.dy + size);
    path.lineTo(center.dx - size * 0.3, center.dy + size * 0.3);
    path.lineTo(center.dx - size, center.dy);
    path.lineTo(center.dx - size * 0.3, center.dy - size * 0.3);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SupportIllustrationPainter oldDelegate) => false;
}