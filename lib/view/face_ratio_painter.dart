import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_mediapipe/gen/landmark.pb.dart';

class FaceRatioPainter extends CustomPainter {
  final List<NormalizedLandmark> landmarks;
  final double elapsedTime;

  FaceRatioPainter({required this.landmarks, required this.elapsedTime});

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.length < 468) return;

    // Create a pulsing animation from 0.4 to 1.0 based on elapsed time
    final double pulse = 0.4 + 0.6 * (0.5 * (1 + sin(elapsedTime * 3)));
    
    final paintLine = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: pulse)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final paintGlow = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: pulse * 0.5)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    final paintDashed = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Helper to get screen coordinates
    Offset getPoint(int index) {
      final p = landmarks[index];
      // Since NativeView uses exact size, scale to widget size
      return Offset(p.x * size.width, p.y * size.height);
    }

    final forehead = getPoint(10);
    final chin = getPoint(152);

    // 1. Vertical Centerline (dashed)
    // From top of forehead, through nose, lips, to chin
    _drawDashedLine(canvas, forehead, chin, paintDashed);

    // 2. Facial Thirds (Horizontal dashed lines)
    // Brow line (using points above the eyes)
    final leftBrow = getPoint(70);
    final rightBrow = getPoint(300);
    _drawDashedLine(canvas, Offset(0, leftBrow.dy), Offset(size.width, rightBrow.dy), paintDashed);
    
    // Base of nose
    final noseBase = getPoint(2);
    _drawDashedLine(canvas, Offset(0, noseBase.dy), Offset(size.width, noseBase.dy), paintDashed);
    
    // Bottom of chin
    _drawDashedLine(canvas, Offset(0, chin.dy), Offset(size.width, chin.dy), paintDashed);

    final paintRed = Paint()
      ..color = Colors.red.withValues(alpha: pulse)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
      
    final paintRedGlow = Paint()
      ..color = Colors.red.withValues(alpha: pulse * 0.5)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    // 3. The 4 Key Measurement Shapes

    // A. The Blue Nose Triangle
    final noseTop = getPoint(168);
    final noseLeft = getPoint(129);
    final noseRight = getPoint(358);

    final pathNoseBlue = Path()
      ..moveTo(noseTop.dx, noseTop.dy)
      ..lineTo(noseLeft.dx, noseLeft.dy)
      ..moveTo(noseTop.dx, noseTop.dy)
      ..lineTo(noseRight.dx, noseRight.dy);
      
    final pathNoseRed = Path()
      ..moveTo(noseLeft.dx, noseLeft.dy)
      ..lineTo(noseRight.dx, noseRight.dy);

    canvas.drawPath(pathNoseBlue, paintGlow);
    canvas.drawPath(pathNoseBlue, paintLine);
    canvas.drawPath(pathNoseRed, paintRedGlow);
    canvas.drawPath(pathNoseRed, paintRed);

    // B. The Inverted Blue Triangle (Eyes to Mouth)
    final leftEyeOuter = getPoint(33);
    final rightEyeOuter = getPoint(263);
    final upperLipCenter = getPoint(13);

    final pathMidFace = Path()
      ..moveTo(leftEyeOuter.dx, leftEyeOuter.dy)
      ..lineTo(rightEyeOuter.dx, rightEyeOuter.dy)
      ..lineTo(upperLipCenter.dx, upperLipCenter.dy)
      ..close();

    canvas.drawPath(pathMidFace, paintGlow);
    canvas.drawPath(pathMidFace, paintLine);

    // C. The Blue Mouth Diamond
    final mouthLeft = getPoint(61);
    final mouthRight = getPoint(291);
    final cupidsBow = getPoint(0);
    final lowerLipCrease = getPoint(17);

    final pathMouth = Path()
      ..moveTo(mouthLeft.dx, mouthLeft.dy)
      ..lineTo(cupidsBow.dx, cupidsBow.dy)
      ..lineTo(mouthRight.dx, mouthRight.dy)
      ..lineTo(lowerLipCrease.dx, lowerLipCrease.dy)
      ..close();

    canvas.drawPath(pathMouth, paintGlow);
    canvas.drawPath(pathMouth, paintLine);

    // D. The Eyebrow Lines
    // Left Eyebrow
    final lBrowIn = getPoint(46);
    final lBrowArch = getPoint(105);
    final lBrowOut = getPoint(107);
    
    // Right Eyebrow
    final rBrowIn = getPoint(276);
    final rBrowArch = getPoint(334);
    final rBrowOut = getPoint(336);

    final pathEyebrowArchRed = Path()
      ..moveTo(lBrowIn.dx, lBrowIn.dy)
      ..lineTo(lBrowArch.dx, lBrowArch.dy)
      ..lineTo(lBrowOut.dx, lBrowOut.dy)
      ..moveTo(rBrowIn.dx, rBrowIn.dy)
      ..lineTo(rBrowArch.dx, rBrowArch.dy)
      ..lineTo(rBrowOut.dx, rBrowOut.dy);

    final pathEyebrowStraightBlue = Path()
      ..moveTo(lBrowIn.dx, lBrowIn.dy)
      ..lineTo(lBrowOut.dx, lBrowOut.dy)
      ..moveTo(rBrowIn.dx, rBrowIn.dy)
      ..lineTo(rBrowOut.dx, rBrowOut.dy);

    canvas.drawPath(pathEyebrowArchRed, paintRedGlow);
    canvas.drawPath(pathEyebrowArchRed, paintRed);
    canvas.drawPath(pathEyebrowStraightBlue, paintGlow);
    canvas.drawPath(pathEyebrowStraightBlue, paintLine);
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dashWidth = 8.0;
    const double dashSpace = 6.0;
    
    final double distance = (p2 - p1).distance;
    if (distance == 0) return;
    
    final dx = (p2.dx - p1.dx) / distance;
    final dy = (p2.dy - p1.dy) / distance;

    // Use elapsed time to shift the dashes, creating a scanning/marching ants effect
    final double dashSpeed = 30.0; // pixels per second
    double startOffset = (elapsedTime * dashSpeed) % (dashWidth + dashSpace);
    
    // Start drawing slightly backwards so we don't have a gap at the start of the line
    double currentDistance = -startOffset;
    
    while (currentDistance < distance) {
      // Don't draw before the start point
      final drawStartDist = currentDistance < 0 ? 0.0 : currentDistance;
      final drawEndDist = (currentDistance + dashWidth > distance) ? distance : currentDistance + dashWidth;
      
      if (drawEndDist > drawStartDist) {
        final startPos = Offset(p1.dx + dx * drawStartDist, p1.dy + dy * drawStartDist);
        final endPos = Offset(p1.dx + dx * drawEndDist, p1.dy + dy * drawEndDist);
        canvas.drawLine(startPos, endPos, paint);
      }
      currentDistance += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
