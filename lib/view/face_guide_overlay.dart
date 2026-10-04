import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'enhanced_face_mesh_camera_screen.dart';

class FaceGuideOverlay extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final FaceState faceState;

  FaceGuideOverlay({
    required this.faces,
    required this.imageSize,
    required this.faceState,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (faces.isNotEmpty) {
      _drawFaceGuide(canvas, size);
    }
  }

  /// 🟢 Draws the center oval guide for user alignment
  void _drawFaceGuide(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final ovalWidth = size.width * 0.6;
    final ovalHeight = size.height * 0.4;

    final ovalRect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: ovalWidth,
      height: ovalHeight,
    );

    final cornerPaint = Paint()
      ..color = faceState == FaceState.ready
          ? Colors.white
          : const Color(0xFFC3002D)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final cornerSize = 30.0;
    final corners = [
      Offset(ovalRect.left, ovalRect.top),
      Offset(ovalRect.right, ovalRect.top),
      Offset(ovalRect.left, ovalRect.bottom),
      Offset(ovalRect.right, ovalRect.bottom),
    ];

    for (final corner in corners) {
      canvas.drawLine(
        corner,
        Offset(
          corner.dx + (corner.dx < centerX ? cornerSize : -cornerSize),
          corner.dy,
        ),
        cornerPaint,
      );
      canvas.drawLine(
        corner,
        Offset(
          corner.dx,
          corner.dy + (corner.dy < centerY ? cornerSize : -cornerSize),
        ),
        cornerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
