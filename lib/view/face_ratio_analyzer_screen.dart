import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_mediapipe/flutter_mediapipe.dart';
import 'package:flutter_mediapipe/gen/landmark.pb.dart';

import 'face_ratio_painter.dart';

class FaceRatioAnalyzerScreen extends StatefulWidget {
  const FaceRatioAnalyzerScreen({super.key});
  @override
  State<FaceRatioAnalyzerScreen> createState() => _FaceRatioAnalyzerScreenState();
}

class _FaceRatioAnalyzerScreenState extends State<FaceRatioAnalyzerScreen> with SingleTickerProviderStateMixin {
  FlutterMediapipe? _mediapipe;
  List<NormalizedLandmark> _landmarks = [];

  double _proportionScore = 0.0;
  double _symmetryScore = 0.0;
  double _ratioScore = 0.0;

  String _cameraFacing = "front";
  Widget? _mediaPipeView;

  late final Ticker _ticker;
  double _elapsedTime = 0.0;

  // FIX #2: Guards against re-entrant camera flips while the GL thread
  // is still tearing down from a previous flip.
  bool _isSwitchingCamera = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((Duration elapsed) {
      setState(() {
        _elapsedTime = elapsed.inMilliseconds / 1000.0;
      });
    })..start();

    _initCamera();
  }

  void _initCamera() {
    _mediaPipeView = KeyedSubtree(
      key: ValueKey(_cameraFacing),
      child: NativeView(
        cameraFacing: _cameraFacing,
        onViewCreated: _onViewCreated,
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onViewCreated(dynamic controller) {
    _mediapipe = controller;
    _mediapipe!.landMarksStream.listen((landmarkList) {
      if (!mounted) return;

      setState(() {
        _landmarks = landmarkList.landmark;
        _calculateScore();
      });
    });
  }

  // ---------------------------------------------------------------------
  // FIX #1: Aspect-ratio-safe geometry.
  // MediaPipe returns normalized (0.0-1.0) coordinates based on the raw
  // camera sensor frame (1280x720), NOT the UI screen size. Scaling by
  // MediaQuery.size stretched the Y axis unevenly and corrupted every
  // ratio calculation. We now scale purely by the camera's native aspect
  // ratio, independent of device/screen size.
  // ---------------------------------------------------------------------
  static const double _cameraAspectRatio = 1280 / 720; // 1.7777...

  double _dist(NormalizedLandmark p1, NormalizedLandmark p2) {
    final dx = (p1.x - p2.x);
    final dy = (p1.y - p2.y) * _cameraAspectRatio;
    return sqrt(dx * dx + dy * dy);
  }

  double _getRatio(double a, double b) {
    if (a == 0 || b == 0) return 0.0;
    return a > b ? a / b : b / a;
  }

  // Scores a ratio against Phi = 1.618
  double _scoreRatio(double ratio) {
    if (ratio <= 0) return 0.0;
    final diff = (ratio - 1.618).abs();
    final score = (1.0 - (diff / 1.618)) * 100.0;
    return score.clamp(0.0, 100.0);
  }

  void _calculateScore() {
    if (_landmarks.length < 468) {
      return;
    }

    final eyeY = (_landmarks[133].y + _landmarks[362].y) / 2.0;

    // NOTE: No per-metric scalar multipliers here. Each ratio below is the
    // actual measured distance ratio from the mesh — nothing is scaled to
    // agree with any external reference score. That means results won't
    // match any specific published number for any specific face, but they
    // WILL be computed the same way for every face, which is the only
    // sense in which a metric like this can be called "correct."

    // 1. Nose Proportions Triangle: eyeline -> nose base (L) vs nostril width (W)
    final noseL = (_landmarks[2].y - eyeY).abs() * _cameraAspectRatio;
    final noseW = _dist(_landmarks[129], _landmarks[358]);
    final noseRatioVal = _getRatio(noseL, noseW);
    final noseScore = _scoreRatio(noseRatioVal);

    // 2. Mid-Face Triangle: outer eye corners (W) vs eyeline -> upper lip (L)
    final midFaceW = _dist(_landmarks[33], _landmarks[263]);
    final midFaceL = (_landmarks[13].y - eyeY).abs() * _cameraAspectRatio;
    final midFaceRatioVal = _getRatio(midFaceW, midFaceL);
    final midFaceScore = _scoreRatio(midFaceRatioVal);

    // 3. Mouth-to-Nose Diamond: mouth width (W) vs nose width (W2)
    // (Mouth width vs mouth HEIGHT was dropped — a relaxed mouth is
    // anatomically ~2.5-3.5x wider than tall, so that ratio can never sit
    // near phi and was only ever forced there by the old scalar hack.
    // Mouth-width-to-nose-width is the actual commonly cited golden-ratio
    // claim, and it's far less sensitive to momentary lip movement.)
    final mouthW = _dist(_landmarks[61], _landmarks[291]);
    final mouthRatioVal = _getRatio(mouthW, noseW);
    final mouthNoseScore = _scoreRatio(mouthRatioVal);

    final finalScore = (noseScore + midFaceScore + mouthNoseScore) / 3.0;

    if (DateTime.now().millisecondsSinceEpoch % 2000 < 50) {
      final jsonOutput = '''
{
  "calculations": {
    "nose_proportions": {
      "ratio": ${noseRatioVal.toStringAsFixed(2)},
      "score_percentage": ${noseScore.toStringAsFixed(2)}
    },
    "mid_face_alignment": {
      "ratio": ${midFaceRatioVal.toStringAsFixed(2)},
      "score_percentage": ${midFaceScore.toStringAsFixed(2)}
    },
    "mouth_to_nose_width": {
      "ratio": ${mouthRatioVal.toStringAsFixed(2)},
      "score_percentage": ${mouthNoseScore.toStringAsFixed(2)}
    }
  },
  "final_average_score": ${finalScore.toStringAsFixed(2)}
}''';
      debugPrint(jsonOutput);
    }

    // Exponential smoothing (Alpha = 0.15) to prevent UI jitter
    if (_proportionScore == 0.0) {
      _proportionScore = finalScore;
      _symmetryScore = midFaceScore;
      _ratioScore = finalScore;
    } else {
      _proportionScore = (0.15 * finalScore) + (0.85 * _proportionScore);
      _symmetryScore = (0.15 * midFaceScore) + (0.85 * _symmetryScore);
      _ratioScore = (0.15 * finalScore) + (0.85 * _ratioScore);
    }
  }

  // ---------------------------------------------------------------------
  // FIX #2: Safe camera flip.
  // Fully unmount NativeView (triggers the plugin's native dispose /
  // GL surface teardown), wait for the GL thread to release the EGL
  // context, THEN remount. Also guards against double-taps re-entering
  // the teardown/rebuild sequence before it completes.
  // ---------------------------------------------------------------------
  void _flipCamera() {
    if (_isSwitchingCamera) return;
    _isSwitchingCamera = true;

    setState(() {
      _cameraFacing = _cameraFacing == "front" ? "back" : "front";
      _landmarks.clear();
      _proportionScore = 0.0;
      _mediaPipeView = null; // fully unmount -> triggers native dispose
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) {
        _isSwitchingCamera = false;
        return;
      }
      setState(() {
        _initCamera();
      });
      _isSwitchingCamera = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Face Ratio Analyzer'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          if (_mediaPipeView != null)
            Positioned.fill(
              child: _mediaPipeView!,
            ),

          Positioned.fill(
            child: CustomPaint(
              painter: FaceRatioPainter(
                landmarks: _landmarks,
                elapsedTime: _elapsedTime,
              ),
            ),
          ),

          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.8), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.cyanAccent.withValues(alpha: 0.2), blurRadius: 10, spreadRadius: 2)
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OVERALL PHI MATCH',
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 10,
                          letterSpacing: 2.0,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _proportionScore > 0 ? '${_proportionScore.toStringAsFixed(1)} %' : 'SCANNING...',
                        style: TextStyle(
                          color: _proportionScore > 85
                              ? Colors.greenAccent
                              : _proportionScore > 70
                              ? Colors.orangeAccent
                              : Colors.redAccent,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildSubScore('SYMMETRY', _symmetryScore),
                          const SizedBox(width: 20),
                          _buildSubScore('GEOMETRY', _ratioScore),
                        ],
                      )
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.flip_camera_android, color: Colors.cyanAccent, size: 30),
                    onPressed: _flipCamera,
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubScore(String label, double score) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white70, fontSize: 9, letterSpacing: 1.5),
        ),
        Text(
          score > 0 ? '${score.toStringAsFixed(1)} %' : '--',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
