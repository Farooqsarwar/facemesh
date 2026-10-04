import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:facemeshcamer/utils/widgets/condition_panel.dart';
import 'package:facemeshcamer/utils/widgets/instructiontext.dart';
import 'package:facemeshcamer/view/face_mesh_painter.dart';
import 'package:facemeshcamer/view/photo_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_mediapipe/flutter_mediapipe.dart';
import 'package:flutter_mediapipe/gen/landmark.pb.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'face_guide_overlay.dart';

enum FaceState { align, hold, ready }

class FaceMeshCameraScreen extends StatefulWidget {
  const FaceMeshCameraScreen({super.key});
  @override
  State<FaceMeshCameraScreen> createState() => _FaceMeshCameraScreenState();
}

class _FaceMeshCameraScreenState extends State<FaceMeshCameraScreen>
    with SingleTickerProviderStateMixin {
  FlutterMediapipe? _mediapipe;
  List<NormalizedLandmark> _landmarks = [];

  FaceState _faceState = FaceState.align;
  int _stabilityCount = 0;
  int _countdown = 0;
  Timer? _countdownTimer;
  bool _isCapturing = false;

  // Face quality conditions
  bool _isCentered = false;
  bool _isGoodSize = false;
  bool _isGoodPose = false;
  bool _areEyesOpen = false;

  // Face bounding box calculated from landmarks
  Rect _faceBoundingBox = Rect.zero;
  double _headEulerAngleY = 0.0; // yaw   (left/right turn)
  double _headEulerAngleZ = 0.0; // roll  (head tilt)
  double _headEulerAngleX = 0.0; // pitch (up/down nod)

  // Smoothed (EMA) values used for decision-making, to avoid single-frame jitter
  double? _smoothYaw;
  double? _smoothRoll;
  double? _smoothPitch;
  double? _smoothLeftEar;
  double? _smoothRightEar;

  // How much weight the newest frame gets in the exponential moving average.
  // Lower = smoother but slower to react, higher = snappier but noisier.
  static const double _smoothingAlpha = 0.35;

  // --- Pitch self-calibration ---
  // A 2D monocular ratio (forehead-to-nose vs nose-to-chin) is NOT a clean,
  // universal proxy for pitch angle — it's skewed by face distance/
  // perspective and varies per face/device. Rather than trusting a fixed
  // "neutral" constant (which was the bug: assumed 0.6, real neutral was
  // ~1.6-1.8 on this device), we sample the user's own neutral ratio for
  // the first few valid frames and measure pitch as a deviation from that
  // personal baseline instead.
  double? _pitchBaselineRatio;
  final List<double> _pitchCalibrationSamples = [];
  static const int _pitchCalibrationFrameCount = 12;
  double _rawVerticalRatio = 1.0;

  bool get _isPitchCalibrated => _pitchBaselineRatio != null;

  late final Ticker _ticker;
  double _elapsedTime = 0.0;

  // ----- MediaPipe FaceMesh (468 pt) landmark indices used for judgment -----
  // Eye corners (horizontal reference for EAR normalization)
  static const int _leftEyeOuter = 33;
  static const int _leftEyeInner = 133;
  static const int _rightEyeInner = 362;
  static const int _rightEyeOuter = 263;

  // Eye vertical pairs (top/bottom lid), 3 pairs per eye for a robust EAR
  static const List<List<int>> _leftEyeVerticalPairs = [
    [159, 145],
    [158, 153],
    [160, 144],
  ];
  static const List<List<int>> _rightEyeVerticalPairs = [
    [386, 374],
    [385, 380],
    [387, 373],
  ];

  // Stable face-oval contour used for bounding box (avoids noisy interior points)
  static const List<int> _faceOvalIndices = [
    10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379,
    378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127,
    162, 21, 54, 103, 67, 109,
  ];

  // Pose reference points
  static const int _noseTip = 1;
  static const int _forehead = 10;
  static const int _chin = 152;
  static const int _leftFaceEdge = 454;
  static const int _rightFaceEdge = 234;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((Duration elapsed) {
      setState(() {
        _elapsedTime = elapsed.inMilliseconds / 1000.0; // seconds
      });
    })..start();
  }

  /// Check if all conditions are satisfied
  bool get _areAllConditionsSatisfied {
    return _isCentered && _isGoodSize && _isGoodPose && _areEyesOpen;
  }

  double _lerp(double? previous, double current, double alpha) {
    if (previous == null) return current;
    return previous + (current - previous) * alpha;
  }

  double _distance(NormalizedLandmark a, NormalizedLandmark b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Calculate face bounding box using the stable face-oval contour only.
  /// Using the full 468-point cloud is noisier (iris jitter, lip motion, etc.)
  /// than the ~36 point oval that defines the actual face silhouette.
  Rect _calculateFaceBoundingBox(List<NormalizedLandmark> landmarks) {
    if (landmarks.length < 468) return Rect.zero;

    double minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0;
    for (final index in _faceOvalIndices) {
      final landmark = landmarks[index];
      if (landmark.x < minX) minX = landmark.x;
      if (landmark.x > maxX) maxX = landmark.x;
      if (landmark.y < minY) minY = landmark.y;
      if (landmark.y > maxY) maxY = landmark.y;
    }

    const padding = 0.03;
    minX = (minX - padding).clamp(0.0, 1.0);
    maxX = (maxX + padding).clamp(0.0, 1.0);
    minY = (minY - padding).clamp(0.0, 1.0);
    maxY = (maxY + padding).clamp(0.0, 1.0);

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Scale-invariant head pose estimation.
  ///
  /// The previous implementation compared raw normalized coordinates against
  /// fixed thresholds, which breaks as soon as the face moves closer/further
  /// from the camera or off-center. Everything here is expressed as a ratio
  /// of two on-face distances (or a true geometric angle), so it stays
  /// accurate regardless of face size or position in frame.
  void _calculateHeadPose(List<NormalizedLandmark> landmarks) {
    if (landmarks.length < 468) return;

    try {
      final noseTip = landmarks[_noseTip];
      final forehead = landmarks[_forehead];
      final chin = landmarks[_chin];
      final leftFace = landmarks[_leftFaceEdge];
      final rightFace = landmarks[_rightFaceEdge];
      final leftEyeOuter = landmarks[_leftEyeOuter];
      final rightEyeOuter = landmarks[_rightEyeOuter];

      // --- Yaw (left/right turn) ---
      // Compare how far the nose sits from each side of the face relative
      // to total face width. A centered nose gives ~0; turning the head
      // shifts the nose toward one edge. This ratio is invariant to how
      // close the face is to the camera.
      final leftWidth = (noseTip.x - leftFace.x).abs();
      final rightWidth = (rightFace.x - noseTip.x).abs();
      final totalWidth = leftWidth + rightWidth;
      _headEulerAngleY =
      totalWidth > 0.0001 ? ((rightWidth - leftWidth) / totalWidth) * 90 : 0.0;

      // --- Roll (head tilt) ---
      // True geometric angle of the eye line vs. horizontal — accurate at
      // any distance/scale, unlike a symmetry-difference heuristic.
      //
      // IMPORTANT: on some front-camera pipelines the landmark stream comes
      // out horizontally mirrored relative to what "left/right eye outer"
      // assumes, which flips dx's sign and makes atan2 report an angle near
      // ±180° for a perfectly level head — so the pose check would fail
      // 100% of the time no matter what the user does. The line's tilt is
      // the same whether we read it left-to-right or right-to-left, so we
      // normalize into the (-90°, 90°] range to remove that ambiguity
      // instead of relying on landmark ordering being "correct".
      final dx = rightEyeOuter.x - leftEyeOuter.x;
      final dy = rightEyeOuter.y - leftEyeOuter.y;
      double roll = math.atan2(dy, dx) * 180 / math.pi;
      if (roll > 90) roll -= 180;
      if (roll < -90) roll += 180;
      _headEulerAngleZ = roll;

      // --- Pitch (up/down nod) ---
      // Ratio of nose-to-forehead vs nose-to-chin distance. This ratio
      // does shift when nodding up/down, but its *neutral* value isn't a
      // fixed constant across faces/devices (confirmed on-device: neutral
      // measured ~1.6-1.8 here, not the previously assumed 0.6) — so we
      // store the raw ratio and convert it to a pitch angle relative to
      // this session's own calibrated neutral value (see
      // _resolvePitchAngle / calibration logic in _analyzeFaceConditions).
      final noseToForehead = (forehead.y - noseTip.y).abs();
      final noseToChin = (noseTip.y - chin.y).abs();
      _rawVerticalRatio =
      noseToChin > 0.0001 ? noseToForehead / noseToChin : _rawVerticalRatio;
    } catch (e) {
      debugPrint("Error calculating pose: $e");
      _headEulerAngleY = 0.0;
      _headEulerAngleZ = 0.0;
      _headEulerAngleX = 0.0;
    }
  }

  /// Eye Aspect Ratio (EAR) — the standard, scale-invariant metric for eye
  /// openness (Soukupová & Čech). Using 3 vertical pairs per eye averaged
  /// together, normalized by the horizontal eye width, makes this robust
  /// to face distance, camera resolution, and minor landmark noise —
  /// unlike a raw absolute-distance threshold.
  double _eyeAspectRatio(
      List<NormalizedLandmark> landmarks, List<List<int>> verticalPairs,
      int outerCorner, int innerCorner) {
    double verticalSum = 0.0;
    for (final pair in verticalPairs) {
      verticalSum += _distance(landmarks[pair[0]], landmarks[pair[1]]);
    }
    final avgVertical = verticalSum / verticalPairs.length;
    final horizontal = _distance(landmarks[outerCorner], landmarks[innerCorner]);
    if (horizontal < 0.0001) return 0.0;
    return avgVertical / horizontal;
  }

  /// Analyze face landmarks to check conditions
  void _analyzeFaceConditions(Size screenSize) {
    if (_landmarks.isEmpty) {
      _isCentered = false;
      _isGoodSize = false;
      _isGoodPose = false;
      _areEyesOpen = false;
      _faceBoundingBox = Rect.zero;
      _smoothYaw = null;
      _smoothRoll = null;
      _smoothPitch = null;
      _smoothLeftEar = null;
      _smoothRightEar = null;
      _pitchBaselineRatio = null;
      _pitchCalibrationSamples.clear();
      return;
    }

    _faceBoundingBox = _calculateFaceBoundingBox(_landmarks);
    _calculateHeadPose(_landmarks);

    // Sample the first few frames to learn this session's neutral pitch
    // ratio before we ever judge pitch. This assumes the user is roughly
    // facing the camera when they start (which matches the intended flow:
    // they're being asked to align their face), and removes the need for
    // any hardcoded "neutral ratio" constant.
    if (!_isPitchCalibrated) {
      _pitchCalibrationSamples.add(_rawVerticalRatio);
      if (_pitchCalibrationSamples.length >= _pitchCalibrationFrameCount) {
        final sum = _pitchCalibrationSamples.reduce((a, b) => a + b);
        _pitchBaselineRatio = sum / _pitchCalibrationSamples.length;
      }
    }

    // Pitch angle = deviation of the current ratio from this session's own
    // neutral baseline, scaled to degree-like units. Until calibration
    // finishes this reads as 0 (treated as neutral) rather than failing.
    _headEulerAngleX = _isPitchCalibrated
        ? (_rawVerticalRatio - _pitchBaselineRatio!) * 50
        : 0.0;

    // Smooth the noisy per-frame signals with an EMA before making
    // pass/fail decisions, so a single bad frame doesn't flip the state.
    _smoothYaw = _lerp(_smoothYaw, _headEulerAngleY, _smoothingAlpha);
    _smoothRoll = _lerp(_smoothRoll, _headEulerAngleZ, _smoothingAlpha);
    _smoothPitch = _lerp(_smoothPitch, _headEulerAngleX, _smoothingAlpha);

    _isCentered = _checkFaceCentered(screenSize);
    _isGoodSize = _checkFaceSize(screenSize);
    _isGoodPose = _checkFacePose();
    _areEyesOpen = _checkEyesOpen();

    // TEMP DEBUG — remove once pose thresholds are confirmed correct.
    // Look at logcat while holding your head straight-on to the camera;
    // yaw/roll/pitch should all read close to 0.
    debugPrint("POSE DEBUG raw(y=${_headEulerAngleY.toStringAsFixed(1)}, "
        "z=${_headEulerAngleZ.toStringAsFixed(1)}, "
        "x=${_headEulerAngleX.toStringAsFixed(1)}) "
        "smooth(y=${_smoothYaw?.toStringAsFixed(1)}, "
        "z=${_smoothRoll?.toStringAsFixed(1)}, "
        "x=${_smoothPitch?.toStringAsFixed(1)}) "
        "pitchCalibrated=$_isPitchCalibrated "
        "(${_pitchCalibrationSamples.length}/$_pitchCalibrationFrameCount) "
        "baseline=${_pitchBaselineRatio?.toStringAsFixed(2)} "
        "pose=$_isGoodPose");
  }

  bool _checkFaceCentered(Size screenSize) {
    if (_faceBoundingBox == Rect.zero) return false;

    final faceCenterX = _faceBoundingBox.center.dx * screenSize.width;
    final faceCenterY = _faceBoundingBox.center.dy * screenSize.height;
    final screenCenterX = screenSize.width / 2;
    final screenCenterY = screenSize.height / 2;

    final centerDistance =
        (Offset(faceCenterX, faceCenterY) - Offset(screenCenterX, screenCenterY))
            .distance;
    final maxDistance = screenSize.width * 0.15;

    return centerDistance < maxDistance;
  }

  bool _checkFaceSize(Size screenSize) {
    if (_faceBoundingBox == Rect.zero) return false;

    final faceWidth = _faceBoundingBox.width * screenSize.width;
    final faceHeight = _faceBoundingBox.height * screenSize.height;

    final minWidth = screenSize.width * 0.25;
    final maxWidth = screenSize.width * 0.6;
    final minHeight = screenSize.height * 0.25;
    final maxHeight = screenSize.height * 0.6;

    return faceWidth >= minWidth &&
        faceWidth <= maxWidth &&
        faceHeight >= minHeight &&
        faceHeight <= maxHeight;
  }

  /// Pose check using the smoothed, scale-invariant angles. Tightened
  /// slightly since the new angle estimates are far less noisy than before,
  /// and requiring the two most important axes (yaw + roll) rather than
  /// "any 2 of 3" avoids accepting a badly pitched face just because yaw
  /// and roll happened to be fine.
  bool _checkFacePose() {
    final yaw = _smoothYaw ?? _headEulerAngleY;
    final roll = _smoothRoll ?? _headEulerAngleZ;
    final pitch = _smoothPitch ?? _headEulerAngleX;

    final bool isGoodYaw = yaw.abs() <= 20;
    final bool isGoodRoll = roll.abs() <= 15;
    final bool isGoodPitch = pitch.abs() <= 20;

    // Yaw and roll must both be good (these matter most for a usable
    // portrait); pitch is allowed a little more slack since nodding
    // slightly rarely ruins a photo.
    return isGoodYaw && isGoodRoll && (isGoodPitch || pitch.abs() <= 25);
  }

  bool _checkEyesOpen() {
    if (_landmarks.length < 468) return false;

    try {
      final leftEarRaw = _eyeAspectRatio(
          _landmarks, _leftEyeVerticalPairs, _leftEyeOuter, _leftEyeInner);
      final rightEarRaw = _eyeAspectRatio(
          _landmarks, _rightEyeVerticalPairs, _rightEyeInner, _rightEyeOuter);

      _smoothLeftEar = _lerp(_smoothLeftEar, leftEarRaw, _smoothingAlpha);
      _smoothRightEar = _lerp(_smoothRightEar, rightEarRaw, _smoothingAlpha);

      // Typical EAR: ~0.28-0.35 open, drops below ~0.15-0.18 when closing.
      // Using the smoothed value avoids false "closed" reads from a single
      // blink-speed frame or momentary landmark jitter.
      const earOpenThreshold = 0.18;

      return (_smoothLeftEar ?? leftEarRaw) > earOpenThreshold &&
          (_smoothRightEar ?? rightEarRaw) > earOpenThreshold;
    } catch (e) {
      debugPrint("Error checking eyes: $e");
      return false;
    }
  }

  bool _areLandmarksValid(List<NormalizedLandmark> landmarks) {
    if (landmarks.isEmpty) return false;

    int outOfBoundsCount = 0;
    for (final landmark in landmarks) {
      if (landmark.x < 0.1 ||
          landmark.x > 0.9 ||
          landmark.y < 0.1 ||
          landmark.y > 0.9) {
        outOfBoundsCount++;
      }
    }

    final double outOfBoundsRatio = outOfBoundsCount / landmarks.length;
    return outOfBoundsRatio < 0.3;
  }

  /// Create a mock Face object for the overlay
  Face get _mockFace {
    return Face(
      boundingBox: Rect.fromLTRB(
        _faceBoundingBox.left,
        _faceBoundingBox.top,
        _faceBoundingBox.right,
        _faceBoundingBox.bottom,
      ),
      headEulerAngleY: _headEulerAngleY,
      headEulerAngleZ: _headEulerAngleZ,
      smilingProbability: null,
      leftEyeOpenProbability: null,
      rightEyeOpenProbability: null,
      trackingId: null,
      landmarks: {},
      contours: {},
    );
  }

  /// Countdown logic
  void _startCountdown() {
    if (_countdown > 0 || _isCapturing || !_areAllConditionsSatisfied) return;

    debugPrint("🎯 Starting countdown - all conditions satisfied!");
    _countdown = 3;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _countdown--;
        debugPrint("Countdown: $_countdown");
        if (_countdown <= 0) {
          timer.cancel();
          _capturePhoto();
        }
      });
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    if (_countdown > 0) {
      debugPrint("❌ Countdown cancelled");
    }
    if (!mounted) {
      _countdown = 0; // still reset internal state safely
      return;
    }
    setState(() => _countdown = 0);
  }

  // Add these to your state class
  final GlobalKey _cameraKey = GlobalKey();

  Future<void> _capturePhoto() async {
    if (_isCapturing) return;
    _isCapturing = true;

    debugPrint("📸 Photo capture triggered - all conditions satisfied!");

    try {
      // Capture the current UI as image
      final boundary =
      _cameraKey.currentContext!.findRenderObject()
      as RenderRepaintBoundary;
      final uiImage = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await uiImage.toByteData(format: ImageByteFormat.png);
      final imageBytes = byteData?.buffer.asUint8List();

      if (imageBytes != null && mounted) {
        // Navigate to preview screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PhotoPreviewScreen(imageBytes: imageBytes),
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ Error capturing photo: $e");
    }

    if (mounted) {
      setState(() => _isCapturing = false);
    }
  }

  String get _instructionText {
    if (_landmarks.isEmpty) return "Richte dein Gesicht auf die Kamera aus";

    if (!_areAllConditionsSatisfied) {
      final missingConditions = [];
      if (!_isCentered) {
        missingConditions.add("richte dein Gesicht in der Mitte aus");
      }
      if (!_isGoodSize) {
        missingConditions.add("gehe auf die richtige Entfernung");
      }
      if (!_isGoodPose) missingConditions.add("halte deinen Kopf gerade");
      if (!_areEyesOpen) missingConditions.add("halte deine Augen offen");

      if (missingConditions.isNotEmpty) {
        return "Bitte ${missingConditions.join(", ")}";
      }
    }

    if (_areAllConditionsSatisfied && _countdown > 0) {
      return "Perfekt! Aufnahme in $_countdown...";
    }

    return "Bitte still halten...";
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 📸 Camera + MediaPipe processing
          Positioned.fill(
            child: RepaintBoundary(
              key: _cameraKey,
              child: NativeView(
                onViewCreated: (controller) {
                  debugPrint("✅ MediaPipe View Created");
                  _mediapipe = controller;

                  _mediapipe!.landMarksStream.listen((landmarkList) {
                    if (!mounted) return;

                    setState(() {
                      _landmarks = landmarkList.landmark;

                      final bool isValidFace = _areLandmarksValid(_landmarks);

                      if (!isValidFace || _landmarks.isEmpty) {
                        _landmarks = [];
                        _isCentered = false;
                        _isGoodSize = false;
                        _isGoodPose = false;
                        _areEyesOpen = false;
                        _faceState = FaceState.align;
                        _stabilityCount = 0;
                        _smoothYaw = null;
                        _smoothRoll = null;
                        _smoothPitch = null;
                        _smoothLeftEar = null;
                        _smoothRightEar = null;
                        _pitchBaselineRatio = null;
                        _pitchCalibrationSamples.clear();
                        _cancelCountdown();
                        return;
                      }

                      _analyzeFaceConditions(screenSize);

                      if (_areAllConditionsSatisfied) {
                        _stabilityCount = (_stabilityCount + 1).clamp(0, 10);
                        if (_stabilityCount >= 3) {
                          _faceState = FaceState.ready;
                          if (_countdown == 0) {
                            _startCountdown();
                          }
                        } else {
                          _faceState = FaceState.hold;
                        }
                      } else {
                        _faceState = FaceState.align;
                        _stabilityCount = 0;
                        _cancelCountdown();
                      }
                    });
                  });
                },
              ),
            ),
          ),

          Positioned.fill(
            child: CustomPaint(
              painter: FaceGuideOverlay(
                faces: _landmarks.isNotEmpty ? [_mockFace] : [],
                imageSize: screenSize,
                faceState: _faceState,
              ),
            ),
          ),

          Positioned.fill(
            child: CustomPaint(
              painter: FaceMeshPainter(
                landmarks: _landmarks.isNotEmpty ? _landmarks : [],
                imageSize: screenSize,
                faceState: _faceState,
                elapsedTime: _elapsedTime,
              ),
            ),
          ),

          InstructionText(instructionText: _instructionText),

          if (_countdown > 0 && _areAllConditionsSatisfied)
            Center(
              child: Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.green, width: 3),
                ),
                child: Text(
                  '$_countdown',
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.of(context).padding.top + 70,
            child: buildConditionsPanel(
              _areAllConditionsSatisfied,
              _isCentered,
              _isGoodSize,
              _isGoodPose,
              _areEyesOpen,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _capturePhoto(),
        child: Icon(Icons.camera),
      ),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }
}