import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/ticket.dart';
import '../services/enhanced_event_service.dart';
import '../services/face_biometric_service.dart';
import 'dart:convert';
import '../services/local_storage_service.dart';

/// Result returned from [FaceVerificationScreen]
class VerificationResult {
  final bool granted;
  final String? attendeeName;
  final double matchPercentage;
  final String ticketId;

  const VerificationResult({
    required this.granted,
    this.attendeeName,
    required this.matchPercentage,
    required this.ticketId,
  });
}

enum _VStep { permission, preview, capturing, result }

/// Full-screen face verification page — same camera style as registration.
/// Pass [targetTicketId] if the QR was scanned; otherwise all active tickets for
/// the event are checked (fallback).
class FaceVerificationScreen extends StatefulWidget {
  final String eventId;
  final String organizerUid;
  final EnhancedEventService eventService;
  final String? targetTicketId; // from QR scan
  final String? qrLandmarksJson; // from QR scan offline storage

  const FaceVerificationScreen({
    super.key,
    required this.eventId,
    required this.organizerUid,
    required this.eventService,
    this.targetTicketId,
    this.qrLandmarksJson,
  });

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;

  _VStep _step = _VStep.permission;
  String _statusMessage = 'Requesting camera permission…';

  // Result
  bool? _granted;
  String _attendeeName = '';
  double _matchPct = 0;
  String _matchedTicketId = '';

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
        _statusMessage = status.isPermanentlyDenied
            ? 'Camera permanently denied — open Settings.'
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
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() {
        _step = _VStep.preview;
        _statusMessage = 'Position your face in the oval and press Verify.';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Camera error: $e');
      }
    }
  }

  Future<void> _captureAndVerify() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _step != _VStep.preview) {
      return;
    }

    setState(() {
      _step = _VStep.capturing;
      _statusMessage = 'Capturing & verifying…';
    });

    try {
      // 1. Take still picture
      final XFile photo = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(photo.path);

      // 2. Detect faces
      final faces = await _faceDetector!.processImage(inputImage);
      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _step = _VStep.preview;
            _statusMessage = 'No face detected — look at the camera and try again.';
          });
        }
        return;
      }

      // 3. Extract live landmarks
      final liveLandmarks =
          FaceBiometricService.extractAndNormalizeLandmarks(faces.first);

      // 4. Get tickets to check
      List<Ticket> ticketsToCheck;
      if (widget.targetTicketId != null) {
        final t = await widget.eventService.getTicketById(widget.targetTicketId!);
        if (t == null || t.status != 'ACTIVE') {
          if (mounted) {
            setState(() {
              _step = _VStep.preview;
              _statusMessage = t == null
                  ? 'Ticket not found.'
                  : 'Ticket status: ${t.status} — not eligible.';
            });
          }
          return;
        }
        ticketsToCheck = [t];
      } else {
        final all = await widget.eventService.getTicketsByEvent(widget.eventId);
        ticketsToCheck = all.where((t) => t.status == 'ACTIVE').toList();
      }

      if (ticketsToCheck.isEmpty) {
        if (mounted) {
          setState(() {
            _step = _VStep.preview;
            _statusMessage = 'No active registrations for this event.';
          });
        }
        return;
      }

      // 5. Compare faces
      Ticket? matchedTicket;
      double bestDistance = double.infinity;

      for (final ticket in ticketsToCheck) {
        List<double>? stored;

        // Offline Zero-Knowledge Proof Approach via QR:
        if (widget.qrLandmarksJson != null && ticket.id == widget.targetTicketId) {
          try {
            final decoded = jsonDecode(widget.qrLandmarksJson!) as List<dynamic>;
            stored = decoded.map((e) => (e as num).toDouble()).toList();
            
            // Validate authenticity: hash the QR payload and match with DB
            final qrHash = FaceBiometricService.generateZkProofHash(stored);
            if (qrHash != ticket.zkProof) {
              // Fraudulent QR Code or Biometrics altered
              stored = null;
            }
          } catch (e) {
            stored = null;
          }
        } 
        
        // Fallback for legacy database coordinates if QR feature was empty
        if (stored == null && ticket.normalizedLandmarksEncrypted != null) {
          try {
            stored = FaceBiometricService.decryptNormalizedLandmarks(
              ticket.normalizedLandmarksEncrypted!,
              ticket.id,
            );
          } catch (_) {}
        }

        stored ??= await LocalStorageService.getFacialFeatures(ticket.id);

        // If no legitimate biometric anchor was resolved, skip this ticket.
        if (stored == null) continue;

        try {
          final dist = FaceBiometricService.calculateEuclideanDistance(
            liveLandmarks,
            stored,
          );
          if (dist < bestDistance) {
            bestDistance = dist;
            if (dist <= FaceBiometricService.similarityThreshold) {
              matchedTicket = ticket;
            }
          }
        } catch (_) {}
      }

      final pct = bestDistance.isInfinite
          ? 0.0
          : ((1.0 - (bestDistance / FaceBiometricService.similarityThreshold)) *
                  100)
              .clamp(0.0, 100.0);

      if (matchedTicket != null) {
        // Grant access
        await widget.eventService.markTicketAsUsed(
          ticketId: matchedTicket.id,
          gatekeeperId: widget.organizerUid,
          euclideanDistance: bestDistance,
        );
        await widget.eventService.logVerificationAttempt(
          ticketId: matchedTicket.id,
          gatekeeperId: widget.organizerUid,
          eventId: widget.eventId,
          hashMatch: true,
          euclideanDistance: bestDistance,
          verificationStatus: 'verified',
        );
        if (mounted) {
          setState(() {
            _granted = true;
            _attendeeName = matchedTicket!.attendeeName;
            _matchPct = pct;
            _matchedTicketId = matchedTicket.id;
            _step = _VStep.result;
          });
        }
      } else {
        await widget.eventService.logVerificationAttempt(
          ticketId: widget.targetTicketId ?? 'unknown',
          gatekeeperId: widget.organizerUid,
          eventId: widget.eventId,
          hashMatch: false,
          euclideanDistance: bestDistance,
          verificationStatus: 'denied',
        );
        if (mounted) {
          setState(() {
            _granted = false;
            _matchPct = pct;
            _step = _VStep.result;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _VStep.preview;
          _statusMessage = 'Error: $e — please try again.';
        });
      }
    }
  }

  void _retake() {
    setState(() {
      _step = _VStep.preview;
      _granted = null;
      _matchPct = 0;
      _statusMessage = 'Position your face in the oval and press Verify.';
    });
  }

  void _done() {
    Navigator.pop(
      context,
      _granted == true
          ? VerificationResult(
              granted: true,
              attendeeName: _attendeeName,
              matchPercentage: _matchPct,
              ticketId: _matchedTicketId,
            )
          : null,
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  // ───────────────── BUILD ─────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Face',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepPurple,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _VStep.permission:
        return _buildPermissionScreen();
      case _VStep.preview:
      case _VStep.capturing:
        return _buildPreviewScreen();
      case _VStep.result:
        return _buildResultScreen();
    }
  }

  // ── Permission ──
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
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _initCamera,
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              label: const Text('Grant Camera Permission',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Camera Preview + Verify Button (same style as registration) ──
  Widget _buildPreviewScreen() {
    final isCapturing = _step == _VStep.capturing;
    return Column(
      children: [
        // Camera view — fills most of screen
        Expanded(
          child: Container(
            color: Colors.black,
            child: _cameraController != null &&
                    _cameraController!.value.isInitialized
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      CameraPreview(_cameraController!),
                      Container(color: Colors.black.withValues(alpha: 0.25)),
                      // Same face guide oval as registration
                      Center(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _VerifyGuidePainter(),
                        ),
                      ),
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
                                  'Verifying identity…',
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

        // Bottom controls — fixed height to prevent overflow
        Container(
          color: Colors.grey[50],
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  border: Border.all(color: Colors.deepPurple.shade200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.deepPurple.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isCapturing ? null : _captureAndVerify,
                  icon: isCapturing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.verified_user, color: Colors.white),
                  label: Text(
                    isCapturing ? 'Verifying…' : 'Verify Face',
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

  // ── Result Screen ──
  Widget _buildResultScreen() {
    final granted = _granted == true;
    return Container(
      color: Colors.black,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Big icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: granted
                        ? [Colors.green.shade400, Colors.green.shade800]
                        : [Colors.red.shade400, Colors.red.shade800],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (granted ? Colors.green : Colors.red)
                          .withValues(alpha: 0.5),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  granted ? Icons.verified : Icons.do_not_disturb_on,
                  color: Colors.white,
                  size: 64,
                ),
              ),
              const SizedBox(height: 28),

              Text(
                granted ? '✅ VERIFIED' : '❌ ENTRY DENIED',
                style: TextStyle(
                  color: granted ? Colors.green.shade300 : Colors.red.shade300,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                granted ? 'ACCESS GRANTED' : 'FACE NOT RECOGNIZED',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w500,
                ),
              ),

              if (granted) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.green.shade600),
                  ),
                  child: Text(
                    _attendeeName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Match: ${_matchPct.toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),

              const SizedBox(height: 40),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _retake,
                      icon: const Icon(Icons.refresh, color: Colors.white70),
                      label: const Text('Try Again',
                          style: TextStyle(color: Colors.white70)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _done,
                      icon: Icon(
                        granted ? Icons.check : Icons.arrow_back,
                        color: Colors.white,
                      ),
                      label: Text(
                        granted ? 'Done' : 'Go Back',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            granted ? Colors.green.shade700 : Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Identical face guide painter to the registration screen:
/// blue oval + corner brackets + label
class _VerifyGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final ovalPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    final ovalW = size.width * 0.62;
    final ovalH = size.height * 0.72;
    final left = (size.width - ovalW) / 2;
    final top = (size.height - ovalH) / 2;
    canvas.drawOval(Rect.fromLTWH(left, top, ovalW, ovalH), ovalPaint);

    final corner = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    const cs = 22.0;
    canvas.drawLine(Offset(left, top), Offset(left + cs, top), corner);
    canvas.drawLine(Offset(left, top), Offset(left, top + cs), corner);
    canvas.drawLine(Offset(left + ovalW, top), Offset(left + ovalW - cs, top), corner);
    canvas.drawLine(Offset(left + ovalW, top), Offset(left + ovalW, top + cs), corner);
    canvas.drawLine(Offset(left, top + ovalH), Offset(left + cs, top + ovalH), corner);
    canvas.drawLine(Offset(left, top + ovalH), Offset(left, top + ovalH - cs), corner);
    canvas.drawLine(Offset(left + ovalW, top + ovalH), Offset(left + ovalW - cs, top + ovalH), corner);
    canvas.drawLine(Offset(left + ovalW, top + ovalH), Offset(left + ovalW, top + ovalH - cs), corner);

    final tp = TextPainter(
      text: const TextSpan(
        text: 'Align your face here',
        style: TextStyle(
            color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, top - 44));
  }

  @override
  bool shouldRepaint(_VerifyGuidePainter old) => false;
}
