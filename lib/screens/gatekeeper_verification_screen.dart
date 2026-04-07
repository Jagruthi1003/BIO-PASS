import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:camera/camera.dart';
import '../models/event.dart';
import '../models/ticket.dart';
import '../services/enhanced_event_service.dart';
import '../services/face_biometric_service.dart';
import '../services/local_storage_service.dart';
import '../services/head_pose_detection_service.dart';

class GatekeeperVerificationScreen extends StatefulWidget {
  final Event event;
  final String gatekeeperId;
  final EnhancedEventService eventService;

  const GatekeeperVerificationScreen({
    super.key,
    required this.event,
    required this.gatekeeperId,
    required this.eventService,
  });

  @override
  State<GatekeeperVerificationScreen> createState() =>
      _GatekeeperVerificationScreenState();
}

class _GatekeeperVerificationScreenState
    extends State<GatekeeperVerificationScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _isProcessing = false;
  String _statusMessage = 'Initialize camera...';
  bool _cameraReady = false;
  // ignore: unused_field
  String? _scannedTicketId;

  // Verification result state
  String _verificationStatus = ''; // 'pending', 'success', 'failure'
  String _verificationMessage = '';
  Ticket? _currentTicket;
  List<double>? _qrLandmarks;
  
  // STABILITY TRACKING: Multi-frame confirmation for robust verification (FIX 5)
  int _consecutiveMatchFrames = 0;      // Number of consecutive frames passing threshold
  int _consecutiveMismatchFrames = 0;   // Number of consecutive frames failing threshold
  static const int _requiredConfirmationFrames = 1; // Require just 1 frame for first-trial acceptance

  late TabController _tabController;
  final TextEditingController _qrInputController = TextEditingController();
  DateTime? _stableFaceSince;
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _scanController;
  bool _qrScanActive = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeCamera();
    _faceDetector = FaceDetector(options: FaceDetectorOptions());
  }

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      _scanController?.pauseCamera();
    }
    _scanController?.resumeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final rearCamera =
          cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back);

      _cameraController = CameraController(
        rearCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController?.initialize();

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Camera ready - Scan QR code';
        _cameraReady = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error initializing camera: $e';
        });
      }
    }
  }

  Future<void> _verifyTicket(String payload) async {
    setState(() {
      _verificationStatus = 'pending';
      _statusMessage = 'Looking up ticket...';
    });

    String ticketId = payload;
    List<double>? parsedLandmarks;

    if (payload.contains('|')) {
      final parts = payload.split('|');
      ticketId = parts[0].trim();
      if (parts.length > 1) {
        try {
          final decoded = jsonDecode(parts[1]) as List<dynamic>;
          parsedLandmarks = decoded.map((e) => (e as num).toDouble()).toList();
        } catch (_) {}
      }
    }

    try {
      // Get ticket from Firestore
      Ticket? ticket = await widget.eventService.getTicketById(ticketId);

      if (ticket == null) {
        setState(() {
          _verificationStatus = 'failure';
          _verificationMessage = '❌ Ticket not found';
          _statusMessage = 'Invalid ticket ID';
        });
        return;
      }

      // Check ticket status
      if (ticket.status != 'ACTIVE') {
        setState(() {
          _verificationStatus = 'failure';
          _verificationMessage = '🔴 Ticket is ${ticket.status}';
          _statusMessage = 'Ticket cannot be used';
        });
        return;
      }

      // If no face data registered yet, show message
      if (ticket.zkProof == null) {
        setState(() {
          _verificationStatus = 'failure';
          _verificationMessage = '⚠️ Face not registered for this ticket';
          _statusMessage = 'Attendee needs to complete face registration';
        });
        return;
      }

      // Check authenticity if QR landmarks were provided
      if (parsedLandmarks != null) {
        final hash = FaceBiometricService.generateZkProofHash(parsedLandmarks);
        if (hash != ticket.zkProof) {
          parsedLandmarks = null; // Fake payload!
        }
      }

      // Decode base64-encoded normalized features from registration
      if (parsedLandmarks == null && ticket.facialFeatures != null) {
        try {
          final decodedBytes = base64Decode(ticket.facialFeatures!);
          final decodedString = utf8.decode(decodedBytes);
          final List<dynamic> jsonList = jsonDecode(decodedString);
          parsedLandmarks = jsonList.map((e) => (e as num).toDouble()).toList();
        } catch (_) {}
      }

      // Fallback decode encrypted landmarks if necessary (legacy)
      if (parsedLandmarks == null && ticket.normalizedLandmarksEncrypted != null) {
        try {
          parsedLandmarks = FaceBiometricService.decryptNormalizedLandmarks(
            ticket.normalizedLandmarksEncrypted!,
            ticket.id,
          );
        } catch (_) {}
      }

      parsedLandmarks ??= await LocalStorageService.getFacialFeatures(ticket.id);

      if (parsedLandmarks == null) {
        setState(() {
          _verificationStatus = 'failure';
          _verificationMessage = '⚠️ Missing biometric data';
          _statusMessage = 'Invalid or altered QR format';
        });
        return;
      }

      setState(() {
        _currentTicket = ticket;
        _qrLandmarks = parsedLandmarks;
      });

      // Switch to camera tab for face verification
      _tabController.animateTo(1);

      setState(() {
        _statusMessage = 'Ready for face verification - Look at camera';
        _verificationMessage = 'Capture your face for verification';
      });

      // Start face detection for verification
      _startFaceVerification(ticket);
    } catch (e) {
      setState(() {
        _verificationStatus = 'failure';
        _verificationMessage = '⚠️ Error: $e';
        _statusMessage = 'Error looking up ticket';
      });
    }
  }

  void _startFaceVerification(Ticket ticket) {
    _cameraController?.startImageStream((image) async {
      if (_isProcessing || _verificationStatus == 'success') return;
      try {
        final inputImage = InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: InputImageRotation.rotation90deg,
            format: InputImageFormat.nv21,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );

        final List<Face> faces = await _faceDetector!.processImage(inputImage);

        if (faces.isEmpty && mounted) {
          _stableFaceSince = null;
          setState(() {
            _statusMessage = 'No face detected - Align face in guide';
          });
          return;
        }

        final now = DateTime.now();
        _stableFaceSince ??= now;

        // Start checking frames immediately if face is detected.
        if (mounted) {
          setState(() {
            _statusMessage = 'Analyzing face... Please look at the camera.';
          });
        }

        _isProcessing = true;
        if (faces.isNotEmpty && mounted) {
          Face face = faces.first;

          try {
            // Detect head pose for guidance and enhanced verification
            Map<String, dynamic> headPose = HeadPoseDetectionService.detectHeadPose(face);
            
            // FIX 1: Remove dual normalization - only use extractAndNormalizeLandmarks
            // extractAndNormalizeLandmarks already normalizes using nose-center + inter-ocular distance
            List<double> liveNormalized = FaceBiometricService.extractAndNormalizeLandmarks(face);

            // Get stored normalized landmarks (already normalized during registration)
            List<double> storedNormalized = _qrLandmarks!;

            // Perform verification with makeup tolerance and head pose verification
            Map<String, dynamic> verificationResult =
                FaceBiometricService.verifyFaceWithEuclideanDistance(
              liveNormalized,
              storedNormalized,
              FaceBiometricService.generateZkProofHash(liveNormalized),
              ticket.zkProof,
            );

            double makeupTolerantDistance = verificationResult['makeupTolerantDistance'] as double;
            
            // Display head pose guidance to user
            String poseInstruction = HeadPoseDetectionService.getInstructionText(headPose);
            if (mounted) {
              setState(() {
                _statusMessage = '$poseInstruction (Distance: ${makeupTolerantDistance.toStringAsFixed(2)})';
              });
            }
            
            // FIX 3 & 5: Implement hysteresis and multi-frame confirmation
            // Use thresholds: pass < 0.75, fail > 0.88, gray zone 0.75-0.88
            bool passThreshold = makeupTolerantDistance < FaceBiometricService.passThreshold;  // 0.75
            bool failThreshold = makeupTolerantDistance >= FaceBiometricService.failThreshold; // 0.88

            if (passThreshold) {
              // Frame passed threshold - increment match counter
              _consecutiveMatchFrames++;
              _consecutiveMismatchFrames = 0; // Reset mismatch counter
              
              // Check if we have enough consecutive matching frames for confirmation
              if (_consecutiveMatchFrames >= _requiredConfirmationFrames) {
                // FIX 5: Face match confirmed over multiple frames! Mark ticket as USED
                bool updateSuccess = await widget.eventService.markTicketAsUsed(
                  ticketId: ticket.id,
                  gatekeeperId: widget.gatekeeperId,
                  euclideanDistance: makeupTolerantDistance,
                );

                // Log verification attempt
                await widget.eventService.logVerificationAttempt(
                  ticketId: ticket.id,
                  gatekeeperId: widget.gatekeeperId,
                  eventId: widget.event.id,
                  hashMatch: verificationResult['hashMatch'] as bool,
                  euclideanDistance: makeupTolerantDistance,
                  verificationStatus: updateSuccess ? 'verified' : 'verification_failed',
                );

                if (updateSuccess && mounted) {
                  setState(() {
                    _verificationStatus = 'success';
                    _verificationMessage =
                        '✅ Entry Granted!\nName: ${ticket.attendeeName}';
                    _statusMessage = 'Face verified - Entry granted';
                  });

                  // Stop camera
                  await _cameraController?.stopImageStream();

                  // Show success animation
                  await Future.delayed(const Duration(seconds: 3));
                  if (mounted) {
                    _resetVerification();
                  }
                } else {
                  setState(() {
                    _verificationStatus = 'failure';
                    _verificationMessage = '⚠️ Ticket update failed';
                    _statusMessage = 'Double-entry detected or ticket already used';
                  });
                  await _cameraController?.stopImageStream();
                  await Future.delayed(const Duration(seconds: 2));
                  if (mounted) {
                    _resetVerification();
                  }
                }
              } else {
                // Still accumulating matches - show progress
                if (mounted) {
                  setState(() {
                    _statusMessage = 
                      'Confirming match... $_consecutiveMatchFrames/$_requiredConfirmationFrames frames';
                  });
                }
              }
            } else if (failThreshold) {
              // Frame clearly failed - reset counters and trigger immediate rejection
              _consecutiveMatchFrames = 0;
              _consecutiveMismatchFrames++;
              
              // Immediate rejection for different faces on first clear mismatch
              if (_consecutiveMismatchFrames >= 1) {
                // Immediate rejection - different face detected
                setState(() {
                  _verificationStatus = 'failure';
                  _verificationMessage =
                      '❌ Face Mismatch\nDistance: ${makeupTolerantDistance.toStringAsFixed(2)}\nEntry Denied';
                  _statusMessage = 'Face does not match registered biometric';
                });

                // Log failed verification
                await widget.eventService.logVerificationAttempt(
                  ticketId: ticket.id,
                  gatekeeperId: widget.gatekeeperId,
                  eventId: widget.event.id,
                  hashMatch: false,
                  euclideanDistance: makeupTolerantDistance,
                  verificationStatus: 'verification_failed',
                  errorMessage: 'Distance exceeded fail threshold - different face detected',
                );

                await _cameraController?.stopImageStream();
                await Future.delayed(const Duration(seconds: 3));
                if (mounted) {
                  _resetVerification();
                }
              } else if (mounted) {
                // Mismatch detected
                setState(() {
                  _statusMessage = 
                    'Mismatch (dist: ${makeupTolerantDistance.toStringAsFixed(2)}). Try again.';
                });
              }
              // Gray zone (0.75-0.88) - could go either way, keep trying
              setState(() {
                _statusMessage = 
                  'Analyzing... Distance: ${makeupTolerantDistance.toStringAsFixed(2)}';
              });
            }
          } catch (e) {
            // FIX 4: Handle landmark extraction errors gracefully
            if (mounted) {
              setState(() {
                _statusMessage = 'Face detection issue: Adjust your position';
              });
            }
          }
        }
        _isProcessing = false;
      } catch (e) {
        setState(() {
          _statusMessage = 'Verification error: $e';
          _verificationMessage = '⚠️ Error during verification';
        });

        // Log error
        if (_currentTicket != null) {
          await widget.eventService.logVerificationAttempt(
            ticketId: _currentTicket!.id,
            gatekeeperId: widget.gatekeeperId,
            eventId: widget.event.id,
            hashMatch: false,
            euclideanDistance: 999.0,
            verificationStatus: 'error',
            errorMessage: e.toString(),
          );
        }

        _isProcessing = false;
      }
    });
  }

  void _resetVerification() {
    setState(() {
      _verificationStatus = '';
      _verificationMessage = '';
      _scannedTicketId = null;
      _currentTicket = null;
      _qrLandmarks = null;
      _statusMessage = 'Ready for next ticket';
      _stableFaceSince = null;
      // Reset frame stability counters (FIX 5)
      _consecutiveMatchFrames = 0;
      _consecutiveMismatchFrames = 0;
    });
    _tabController.animateTo(0);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _scanController?.dispose();
    _faceDetector?.close();
    _tabController.dispose();
    _qrInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gatekeeper - ${widget.event.name}'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Event Info Bar
          Container(
            color: Colors.blue[50],
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.event, color: Colors.blue[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.event.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.event.location,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Tabs
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Scan QR'),
              Tab(text: 'Face Verify'),
            ],
          ),
          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // QR Scanning Tab
                _buildQrScanTab(),
                // Face Verification Tab
                _buildFaceVerifyTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrScanTab() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.qr_code_2, size: 80, color: Colors.blue[300]),
                  const SizedBox(height: 20),
                  const Text(
                    'Scan Attendee QR Code',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (_qrScanActive)
                    SizedBox(
                      height: 300,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: QRView(
                          key: _qrKey,
                          onQRViewCreated: (controller) {
                            setState(() {
                              _scanController = controller;
                            });
                            controller.resumeCamera();
                            controller.scannedDataStream.listen((scanData) async {
                              final code = scanData.code;
                              if (code == null || code.isEmpty) return;
                              await _scanController?.pauseCamera();
                              if (mounted) {
                                setState(() {
                                  _qrScanActive = false;
                                });
                                _verifyTicket(code);
                              }
                            });
                          },
                          overlay: QrScannerOverlayShape(
                            borderColor: Colors.blue,
                            borderRadius: 10,
                            borderLength: 30,
                            borderWidth: 4,
                            cutOutSize: 200,
                          ),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() => _qrScanActive = true),
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan Mandatory QR Code'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  // Recent verification result (if any)
                  if (_verificationStatus.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _verificationStatus == 'success'
                            ? Colors.green[50]
                            : Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _verificationStatus == 'success'
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _verificationMessage,
                            style: TextStyle(
                              color: _verificationStatus == 'success'
                                  ? Colors.green[700]
                                  : Colors.red[700],
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_currentTicket != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Attendee: ${_currentTicket!.attendeeName}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFaceVerifyTab() {
    if (!_cameraReady) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        // Camera Preview
        CameraPreview(_cameraController!),
        // Face Guide Overlay
        Center(
          child: CustomPaint(
            size: Size.infinite,
            painter: FaceGuidePainter(),
          ),
        ),
        // Status Overlay
        if (_verificationStatus.isNotEmpty)
          Container(
            color: Colors.black.withValues(alpha: 0.4),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _verificationStatus == 'success'
                      ? Colors.green
                      : Colors.red,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _verificationStatus == 'success'
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: Colors.white,
                      size: 64,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _verificationMessage.split('\n')[0],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_verificationMessage.split('\n').length > 1) ...[
                      const SizedBox(height: 8),
                      Text(
                        _verificationMessage.split('\n').sublist(1).join('\n'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        // Top Status
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _statusMessage,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

class FaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final ovalWidth = size.width * 0.6;
    final ovalHeight = size.height * 0.7;

    final left = (size.width - ovalWidth) / 2;
    final top = (size.height - ovalHeight) / 2;

    final rect = Rect.fromLTWH(left, top, ovalWidth, ovalHeight);
    canvas.drawOval(rect, paint);

    // Corner markers
    final cornerPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    const cornerSize = 20.0;

    // Corners
    for (var dx in [-1.0, 1.0]) {
      for (var dy in [-1.0, 1.0]) {
        final cx = left + ovalWidth * (dx + 1) / 2;
        final cy = top + ovalHeight * (dy + 1) / 2;

        canvas.drawLine(
          Offset(cx - cornerSize * dx, cy),
          Offset(cx, cy),
          cornerPaint,
        );
        canvas.drawLine(
          Offset(cx, cy - cornerSize * dy),
          Offset(cx, cy),
          cornerPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(FaceGuidePainter oldDelegate) => false;
}
