import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_mediapipe/gen/landmark.pb.dart';

import '../utils/connections.dart';
import 'enhanced_face_mesh_camera_screen.dart';

enum MeshState {
  appearing,
  visible,
  destroying,
  hidden,
}

class ParticleData {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  double opacity;
  Color color;
  double life;
  double rotation;
  double rotationSpeed;

  ParticleData({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.opacity,
    required this.color,
    required this.life,
    this.rotation = 0,
    this.rotationSpeed = 0,
  });

  void update(double dt) {
    x += vx * dt;
    y += vy * dt;
    vy += 150 * dt; // Gravity
    vx *= 0.98; // Air resistance
    life -= dt;
    opacity = (life / 1.2).clamp(0.0, 1.0);
    size *= 0.995;
    rotation += rotationSpeed * dt;
  }

  bool get isDead => life <= 0 || opacity <= 0 || size < 0.5;
}

class FaceMeshPainter extends CustomPainter {
  final List<NormalizedLandmark> landmarks;
  final Size imageSize;
  final FaceState faceState;
  final double elapsedTime;
  final MeshState meshState;
  final double meshTransitionProgress;
  final List<ParticleData>? destructionParticles;
  final List<NormalizedLandmark>? lastLandmarks;

  FaceMeshPainter({
    required this.landmarks,
    required this.imageSize,
    required this.faceState,
    required this.elapsedTime,
    this.meshState = MeshState.visible,
    this.meshTransitionProgress = 1.0,
    this.destructionParticles,
    this.lastLandmarks,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw destruction particles
    if ((meshState == MeshState.destroying || meshState == MeshState.hidden) &&
        destructionParticles != null &&
        destructionParticles!.isNotEmpty) {
      _drawDestructionParticles(canvas, size);
    }

    // Use last landmarks during destruction for smooth transition
    final activeLandmarks = landmarks.isNotEmpty
        ? landmarks
        : (meshState == MeshState.destroying && lastLandmarks != null
        ? lastLandmarks!
        : <NormalizedLandmark>[]);

    if (activeLandmarks.isEmpty && meshState != MeshState.destroying) return;
    if (activeLandmarks.isEmpty) return;

    final imageAspect = imageSize.width / imageSize.height;
    final canvasAspect = size.width / size.height;

    double scaleX = size.width;
    double scaleY = size.height;
    double offsetX = 0;
    double offsetY = 0;

    if (canvasAspect > imageAspect) {
      scaleX = size.height * imageAspect;
      offsetX = (size.width - scaleX) / 2;
      scaleY = size.height;
    } else {
      scaleY = size.width / imageAspect;
      offsetY = (size.height - scaleY) / 2;
      scaleX = size.width;
    }

    const widenFactor = 1.15;
    final widenedScaleX = scaleX * widenFactor;
    final widenedOffsetX = offsetX - ((widenedScaleX - scaleX) / 2);

    final yValues = activeLandmarks.map((l) => l.y).toList();
    final yMin = yValues.reduce(min);
    final yMax = yValues.reduce(max);
    final xValues = activeLandmarks.map((l) => l.x).toList();
    final xMin = xValues.reduce(min);
    final xMax = xValues.reduce(max);

    const double waveDuration = 4.0;
    final double cycle = (elapsedTime % waveDuration) / waveDuration;
    final double fillHeight = 1.0 - cycle;
    const double transitionSmoothness = 0.2;

    // Calculate transition effects
    double globalOpacity = 1.0;
    double scatterFactor = 0.0;
    double fragmentProgress = 0.0;

    if (meshState == MeshState.appearing) {
      globalOpacity = Curves.easeOutCubic.transform(meshTransitionProgress);
    } else if (meshState == MeshState.destroying) {
      final destroyProgress = meshTransitionProgress;
      globalOpacity = Curves.easeInCubic.transform(1.0 - destroyProgress);
      scatterFactor = Curves.easeInQuad.transform(destroyProgress) * 80.0;
      fragmentProgress = destroyProgress;
    }

    if (globalOpacity <= 0.01) return;

    // Colors - High tech HUD aesthetics
    final baseColor = (faceState == FaceState.ready)
        ? const Color(0xFF00E5FF).withValues(alpha: 0.35 * globalOpacity) // Neon Cyan
        : const Color(0xFFFF3D00).withValues(alpha: 0.35 * globalOpacity); // Neon Orange

    final waveColor = (faceState == FaceState.ready)
        ? const Color(0xFF69F0AE).withValues(alpha: 0.95 * globalOpacity) // Neon Green
        : const Color(0xFFFF0000).withValues(alpha: 0.95 * globalOpacity); // Neon Red

    final random = Random(42 + (elapsedTime * 10).toInt());

    // Calculate scattered position
    Offset getScatteredOffset(double px, double py, int index, double centerX, double centerY) {
      if (scatterFactor == 0) return Offset(px, py);

      // Direction away from center
      final dx = px - centerX;
      final dy = py - centerY;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist < 1) return Offset(px, py);

      final normalizedDx = dx / dist;
      final normalizedDy = dy / dist;

      // Add randomness
      final randomAngle = (random.nextDouble() - 0.5) * 0.5;
      final rotatedDx = normalizedDx * cos(randomAngle) - normalizedDy * sin(randomAngle);
      final rotatedDy = normalizedDx * sin(randomAngle) + normalizedDy * cos(randomAngle);

      final scatterDist = scatterFactor * (0.5 + random.nextDouble() * 0.5);

      return Offset(
        px + rotatedDx * scatterDist,
        py + rotatedDy * scatterDist,
      );
    }

    const faceBoundaryIndices = [
      10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
      397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
      172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109, 10
    ];

    // Calculate center for scatter effect
    final centerX = widenedOffsetX + ((xMin + xMax) / 2 * widenedScaleX);
    final centerY = offsetY + ((yMin + yMax) / 2 * scaleY);

    // Create clip path
    final boundaryClipPath = Path();
    bool firstBoundary = true;
    for (final index in faceBoundaryIndices) {
      if (index < activeLandmarks.length) {
        final p = activeLandmarks[index];
        var px = widenedOffsetX + (p.x * widenedScaleX);
        var py = offsetY + (p.y * scaleY);

        if (scatterFactor > 0) {
          final scattered = getScatteredOffset(px, py, index, centerX, centerY);
          px = scattered.dx;
          py = scattered.dy;
        }

        if (firstBoundary) {
          boundaryClipPath.moveTo(px, py);
          firstBoundary = false;
        } else {
          boundaryClipPath.lineTo(px, py);
        }
      }
    }
    boundaryClipPath.close();

    // Clip canvas (skip during heavy destruction)
    canvas.save();
    if (scatterFactor < 30) {
      canvas.clipPath(boundaryClipPath);
    }

    // Draw ambient glow
    if (globalOpacity > 0.3 && meshState != MeshState.destroying) {
      final glowPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = waveColor.withValues(alpha: 0.08 * globalOpacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 25);
      canvas.drawPath(boundaryClipPath, glowPaint);
    }

    final faceRect = Rect.fromLTRB(
      widenedOffsetX, 
      offsetY + yMin * scaleY, 
      widenedOffsetX + widenedScaleX, 
      offsetY + yMax * scaleY
    );

    final safeStart = (fillHeight - transitionSmoothness).clamp(0.0, 1.0);
    final safeEnd = fillHeight.clamp(0.0, 1.0);
    final safeFade = (fillHeight + 0.1).clamp(0.0, 1.0);

    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        baseColor,
        waveColor,
        baseColor,
      ],
      stops: [
        safeStart,
        safeEnd,
        safeFade,
      ],
    ).createShader(faceRect);

    // Draw boundary outline using the same shader
    final boundaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..shader = shader;

    final glowBoundaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12.0
      ..strokeCap = StrokeCap.round
      ..shader = shader
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);

    if (scatterFactor < 30) {
      if (meshState != MeshState.destroying) {
        canvas.drawPath(boundaryClipPath, glowBoundaryPaint);
      }
      canvas.drawPath(boundaryClipPath, boundaryPaint);
    }

    // Draw triangulated mesh wireframe
    if (scatterFactor < 30 && activeLandmarks.length > 100) {
      final meshLinePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..shader = shader
        ..strokeCap = StrokeCap.round;

      final meshGlowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);

      final drawnEdges = <int>{};
      final meshPath = Path();

      for (final edge in connections) {
        if (edge.length < 2) continue;
        final a = edge[0];
        final b = edge[1];
        if (a >= activeLandmarks.length || b >= activeLandmarks.length) continue;

        final edgeKey = a < b ? (a << 16) | b : (b << 16) | a;
        if (!drawnEdges.add(edgeKey)) continue;

        if (fragmentProgress > 0 && (random.nextDouble() < fragmentProgress || random.nextDouble() < fragmentProgress)) continue;

        final pa = activeLandmarks[a];
        final pb = activeLandmarks[b];
        var ax = widenedOffsetX + pa.x * widenedScaleX;
        var ay = offsetY + pa.y * scaleY;
        var bx = widenedOffsetX + pb.x * widenedScaleX;
        var by = offsetY + pb.y * scaleY;

        if (scatterFactor > 0) {
          final sa = getScatteredOffset(ax, ay, a, centerX, centerY);
          final sb = getScatteredOffset(bx, by, b, centerX, centerY);
          ax = sa.dx; ay = sa.dy;
          bx = sb.dx; by = sb.dy;
        }

        meshPath.moveTo(ax, ay);
        meshPath.lineTo(bx, by);
      }

      if (meshState != MeshState.destroying) {
        canvas.drawPath(meshPath, meshGlowPaint);
      }
      canvas.drawPath(meshPath, meshLinePaint);
    }

    // Draw landmark dots efficiently for a clean constellation effect
    final dotsPath = Path();
    for (int i = 0; i < activeLandmarks.length; i += 2) {
      if (fragmentProgress > 0 && random.nextDouble() < fragmentProgress) continue;
      
      final p = activeLandmarks[i];
      var px = widenedOffsetX + p.x * widenedScaleX;
      var py = offsetY + p.y * scaleY;
      
      if (scatterFactor > 0) {
        final s = getScatteredOffset(px, py, i, centerX, centerY);
        px = s.dx; py = s.dy;
      }
      
      dotsPath.addOval(Rect.fromCircle(center: Offset(px, py), radius: 1.2));
    }
    
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = shader;
    
    canvas.drawPath(dotsPath, dotPaint);

    canvas.restore();

    // Draw energy pulses (only when visible)
    if (meshState == MeshState.visible && globalOpacity > 0.5) {
      _drawEnergyPulses(
        canvas, activeLandmarks, widenedOffsetX, widenedScaleX,
        offsetY, scaleY, waveColor, elapsedTime, globalOpacity,
      );
    }
  }

  void _drawEnergyPulses(
      Canvas canvas,
      List<NormalizedLandmark> landmarks,
      double widenedOffsetX, double widenedScaleX,
      double offsetY, double scaleY,
      Color waveColor, double elapsedTime, double globalOpacity,
      ) {
    const keyPoints = [4, 168, 6, 197, 195, 5];

    for (int i = 0; i < keyPoints.length; i++) {
      final index = keyPoints[i];
      if (index < landmarks.length) {
        final point = landmarks[index];
        final px = widenedOffsetX + (point.x * widenedScaleX);
        final py = offsetY + (point.y * scaleY);

        final pulsePhase = (elapsedTime + i * 0.4) % 2.5;
        final pulseSize = pulsePhase < 1.2
            ? Curves.easeOut.transform(pulsePhase / 1.2) * 18
            : Curves.easeIn.transform((2.5 - pulsePhase) / 1.3) * 18;
        final pulseOpacity = pulsePhase < 1.2
            ? 1.0 - (pulsePhase / 1.2)
            : (pulsePhase - 1.2) / 1.3;

        if (pulseSize > 1) {
          final pulsePaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = waveColor.withValues(alpha:
                (pulseOpacity * 0.4 * globalOpacity).clamp(0.0, 1.0));

          canvas.drawCircle(Offset(px, py), pulseSize, pulsePaint);
        }
      }
    }
  }

  void _drawDestructionParticles(Canvas canvas, Size size) {
    if (destructionParticles == null) return;

    for (final particle in destructionParticles!) {
      if (particle.opacity <= 0) continue;

      // Trail effect
      final trailPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = particle.color.withValues(alpha: (particle.opacity * 0.3).clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

      canvas.drawCircle(
        Offset(particle.x - particle.vx * 0.02, particle.y - particle.vy * 0.02),
        particle.size * 0.6,
        trailPaint,
      );

      // Main particle
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = particle.color.withValues(alpha: particle.opacity.clamp(0.0, 1.0));

      canvas.drawCircle(
        Offset(particle.x, particle.y),
        particle.size,
        paint,
      );

      // Bright center
      if (particle.size > 2) {
        final centerPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.white.withValues(alpha: (particle.opacity * 0.6).clamp(0.0, 1.0));
        canvas.drawCircle(
          Offset(particle.x, particle.y),
          particle.size * 0.3,
          centerPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant FaceMeshPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.faceState != faceState ||
        oldDelegate.elapsedTime != elapsedTime ||
        oldDelegate.meshState != meshState ||
        oldDelegate.meshTransitionProgress != meshTransitionProgress ||
        oldDelegate.destructionParticles != destructionParticles;
  }
}