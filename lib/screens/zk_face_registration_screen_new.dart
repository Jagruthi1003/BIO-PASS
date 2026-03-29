import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/face_biometric_service.dart';
import '../services/enhanced_event_service.dart';
import '../services/local_storage_service.dart';

// Registration flow states
enum _RegStep { permission, preview, capturing, captured, registering, done }

class ZkFaceRegistrationScreenNew extends StatefulWidget {
  final String ticketId;
  final String eventId;
  final EnhancedEventService eventService;

  const ZkFaceRegistrationScreenNew({
    super.key,
    required this.ticketId,
    required this.eventId,
    required this.eventService,
  });

  @override
  State<ZkFaceRegistrationScreenNew> createState() =>
      _ZkFaceRegistrationScreenNewState();
}

class _ZkFaceRegistrationScreenNewState
    extends State<ZkFaceRegistrationScreenNew> {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;

  _RegStep _step = _RegStep.permission;
  String _statusMessage = 'Requesting camera permission…';
  String? _errorMessage;

  // Captured data (in-memory only — NOT yet saved to DB)
  List<double>? _capturedLandmarks;
  String? _capturedZkProof;
  int _landmarkCount = 0;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;

    if (!status.isGranted) {
      setState(() {
        _step = _RegStep.permission;
        _statusMessage = status.isPermanentlyDenied
            ? 'Camera permanently denied — open Settings to allow.'
            : 'Camera permission required.';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      CameraDescription camera;
      try {
        camera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
        );
      } catch (_) {
        camera = cameras.first;
      }

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium, // medium gives better ByteBuffer compatibility
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _cameraController!.initialize();

      if (!mounted) { return; }
      setState(() {
        _step = _RegStep.preview;
        _statusMessage = 'Position your face in the oval frame and press Capture.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _RegStep.permission;
          _statusMessage = 'Camera error: $e';
        });
      }
    }
  }

  /// Takes a still JPEG picture and runs ML Kit on the file path.
  /// This avoids the NV21 ByteBuffer format mismatch on most Android devices.
  Future<void> _captureFace() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _step != _RegStep.preview) {
      return;
    }

    setState(() {
      _step = _RegStep.capturing;
      _statusMessage = 'Capturing…';
      _errorMessage = null;
    });

    try {
      // 1. Take a still picture — JPEG on any Android/iOS
      final XFile photo = await _cameraController!.takePicture();

      // 2. Build InputImage from file path (avoids ByteBuffer format issues)
      final inputImage = InputImage.fromFilePath(photo.path);

      // 3. Detect faces
      final faces = await _faceDetector!.processImage(inputImage);

      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _step = _RegStep.preview;
            _statusMessage = 'No face detected — look at the camera and try again.';
            _errorMessage = 'No face found in the image.';
          });
        }
        return;
      }

      final face = faces.first;

      // 4. Extract + normalize landmarks — kept in memory ONLY
      final landmarks = FaceBiometricService.extractAndNormalizeLandmarks(face);
      final zkProof = FaceBiometricService.generateZkProofHash(landmarks);

      if (mounted) {
        setState(() {
          _capturedLandmarks = landmarks;
          _capturedZkProof = zkProof;
          _landmarkCount = landmarks.length ~/ 2;
          _step = _RegStep.captured;
          _statusMessage = 'Face captured! Review below, then tap Register.';
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _RegStep.preview;
          _statusMessage = 'Error capturing face — try again.';
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _retake() {
    setState(() {
      _capturedLandmarks = null;
      _capturedZkProof = null;
      _landmarkCount = 0;
      _step = _RegStep.preview;
      _statusMessage = 'Position your face in the oval frame and press Capture.';
      _errorMessage = null;
    });
  }

  /// Saves the captured biometric data to Firestore — only called explicitly.
  Future<void> _registerFace() async {
    if (_capturedLandmarks == null || _capturedZkProof == null) {
      return;
    }

    setState(() {
      _step = _RegStep.registering;
      _statusMessage = 'Saving your face registration…';
    });

    try {
      // Save original landmarks strictly dynamically and locally
      await LocalStorageService.saveFacialFeatures(widget.ticketId, _capturedLandmarks!);

      await widget.eventService.updateTicketWithBiometrics(
        ticketId: widget.ticketId,
        zkProof: _capturedZkProof!,
      );

      if (mounted) {
        setState(() {
          _step = _RegStep.done;
          _statusMessage = '✅ Face registered successfully!';
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _RegStep.captured;
          _statusMessage = 'Registration failed — tap Register to retry.';
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  // ─────────────────────────── BUILD ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Your Face'),
        backgroundColor: const Color(0xFF2D3E50),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _RegStep.permission:
        return _buildPermissionScreen();
      case _RegStep.preview:
      case _RegStep.capturing:
        return _buildPreviewScreen();
      case _RegStep.captured:
        return _buildCapturedScreen();
      case _RegStep.registering:
        return _buildProcessingScreen('Saving registration…');
      case _RegStep.done:
        return _buildProcessingScreen('✅ Registered!');
    }
  }

  // ─── Permission screen ───
  Widget _buildPermissionScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt, size: 80, color: Colors.deepPurple.shade300),
            const SizedBox(height: 24),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _initCamera,
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              label: const Text(
                'Grant Camera Permission',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            if (_statusMessage.contains('Settings')) ...[
              const SizedBox(height: 12),
              const TextButton(
                onPressed: openAppSettings,
                child: Text('Open App Settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Camera Preview + Capture Button ───
  Widget _buildPreviewScreen() {
    final isCapturing = _step == _RegStep.capturing;
    return Column(
      children: [
        // Camera preview — fills most of screen
        Expanded(
          child: Container(
            color: Colors.black,
            child: _cameraController != null &&
                    _cameraController!.value.isInitialized
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      CameraPreview(_cameraController!),
                      // Darkened border overlay
                      Container(color: Colors.black.withValues(alpha: 0.25)),
                      // Face guide oval
                      Center(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _FaceGuidePainter(detected: false),
                        ),
                      ),
                      // Loading overlay while taking picture
                      if (isCapturing)
                        Container(
                          color: Colors.black.withValues(alpha: 0.55),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Colors.white),
                                SizedBox(height: 16),
                                Text(
                                  'Analyzing face…',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
          ),
        ),

        // Bottom controls — fixed height, no overflow
        Container(
          color: Colors.grey[50],
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status / error
              _StatusBox(
                message: _statusMessage,
                isError: _errorMessage != null,
              ),
              const SizedBox(height: 10),

              // Instructions
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  border: Border.all(color: Colors.deepPurple.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '📸 Tips:  Face the camera • Good lighting • Keep still',
                  style: TextStyle(fontSize: 12, color: Colors.deepPurple, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),

              // Capture button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isCapturing ? null : _captureFace,
                  icon: isCapturing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.camera_alt, color: Colors.white),
                  label: Text(
                    isCapturing ? 'Capturing…' : 'Capture Face',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    disabledBackgroundColor: Colors.deepPurple.shade200,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Captured confirmation screen ───
  Widget _buildCapturedScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
          const SizedBox(height: 16),
          const Text(
            'Face Captured!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Face data is ready in memory.\nTap Register to save and complete your booking.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),

          // Landmark summary card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Captured Data',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const Divider(),
                  _infoRow(Icons.grain, 'Landmarks detected', '$_landmarkCount points'),
                  _infoRow(Icons.lock_outline, 'Encryption', 'AES-256-CBC'),
                  _infoRow(Icons.fingerprint, 'ZK-proof hash', 'SHA-256 ✓'),
                  _infoRow(Icons.cloud_off, 'Saved to server?', 'Not yet — pending your approval'),
                ],
              ),
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                border: Border.all(color: Colors.red),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Retake + Register buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _retake,
                  icon: const Icon(Icons.camera_alt, color: Colors.deepPurple),
                  label: const Text(
                    'Retake',
                    style: TextStyle(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.deepPurple, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _registerFace,
                  icon: const Icon(Icons.how_to_reg, color: Colors.white),
                  label: const Text(
                    'Register',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Processing / Done screen ───
  Widget _buildProcessingScreen(String message) {
    final bool isDone = _step == _RegStep.done;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          isDone
              ? const Icon(Icons.verified, size: 100, color: Colors.green)
              : const CircularProgressIndicator(color: Colors.deepPurple),
          const SizedBox(height: 24),
          Text(
            message,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.deepPurple),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Face guide oval painter ───
class _FaceGuidePainter extends CustomPainter {
  final bool detected;
  _FaceGuidePainter({this.detected = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (detected ? Colors.green : Colors.blue).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    final ovalW = size.width * 0.62;
    final ovalH = size.height * 0.72;
    final left = (size.width - ovalW) / 2;
    final top = (size.height - ovalH) / 2;
    canvas.drawOval(Rect.fromLTWH(left, top, ovalW, ovalH), paint);

    // Corner dashes
    final corner = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    const cs = 22.0;
    // TL
    canvas.drawLine(Offset(left, top), Offset(left + cs, top), corner);
    canvas.drawLine(Offset(left, top), Offset(left, top + cs), corner);
    // TR
    canvas.drawLine(Offset(left + ovalW, top), Offset(left + ovalW - cs, top), corner);
    canvas.drawLine(Offset(left + ovalW, top), Offset(left + ovalW, top + cs), corner);
    // BL
    canvas.drawLine(Offset(left, top + ovalH), Offset(left + cs, top + ovalH), corner);
    canvas.drawLine(Offset(left, top + ovalH), Offset(left, top + ovalH - cs), corner);
    // BR
    canvas.drawLine(Offset(left + ovalW, top + ovalH), Offset(left + ovalW - cs, top + ovalH), corner);
    canvas.drawLine(Offset(left + ovalW, top + ovalH), Offset(left + ovalW, top + ovalH - cs), corner);

    // Label
    final tp = TextPainter(
      text: const TextSpan(
        text: 'Align your face here',
        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, top - 44));
  }

  @override
  bool shouldRepaint(_FaceGuidePainter old) => detected != old.detected;
}

// ─── Shared status box widget ───
class _StatusBox extends StatelessWidget {
  final String message;
  final bool isError;
  const _StatusBox({required this.message, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? Colors.red[50] : Colors.deepPurple[50],
        border: Border.all(
          color: isError ? Colors.red : Colors.deepPurple,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          color: isError ? Colors.red[800] : Colors.deepPurple[900],
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
