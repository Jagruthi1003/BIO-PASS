import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';
import '../models/event.dart';
import '../models/ticket.dart';
import '../services/enhanced_event_service.dart';
import '../services/face_biometric_service.dart';

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

  late TabController _tabController;
  final TextEditingController _qrInputController = TextEditingController();
  DateTime? _stableFaceSince;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeCamera();
    _faceDetector = FaceDetector(options: FaceDetectorOptions());
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

  Future<void> _verifyTicket(String ticketId) async {
    setState(() {
      _verificationStatus = 'pending';
      _statusMessage = 'Looking up ticket...';
    });

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

      setState(() {
        _currentTicket = ticket;
      });

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
      if (ticket.zkProof == null || ticket.normalizedLandmarksEncrypted == null) {
        setState(() {
          _verificationStatus = 'failure';
          _verificationMessage = '⚠️ Face not registered for this ticket';
          _statusMessage = 'Attendee needs to complete face registration';
        });
        return;
      }

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
        final stableMs = now.difference(_stableFaceSince!).inMilliseconds;
        if (stableMs < 1500) {
          if (mounted) {
            setState(() {
              _statusMessage =
                  'Face detected. Hold steady for ${(1.5 - (stableMs / 1000)).clamp(0, 1.5).toStringAsFixed(1)}s';
            });
          }
          return;
        }

        _isProcessing = true;
        if (faces.isNotEmpty && mounted) {
          Face face = faces.first;

          // Extract and normalize live landmarks
          List<double> liveNormalized =
              FaceBiometricService.extractAndNormalizeLandmarks(face);

          // Generate live ZK proof
          String liveZkHash = FaceBiometricService.generateZkProofHash(liveNormalized);

          // Decrypt stored landmarks
          List<double> storedNormalized =
              FaceBiometricService.decryptNormalizedLandmarks(
            ticket.normalizedLandmarksEncrypted!,
            ticket.id,
          );

          // Calculate Euclidean distance
          double distance = FaceBiometricService.calculateEuclideanDistance(
            liveNormalized,
            storedNormalized,
          );

          // Perform verification
          Map<String, dynamic> verificationResult =
              FaceBiometricService.verifyFaceWithEuclideanDistance(
            liveNormalized,
            storedNormalized,
            liveZkHash,
            ticket.zkProof,
          );

          bool isMatch = verificationResult['isMatch'] as bool;

          if (isMatch) {
            // Face match! Mark ticket as USED in atomic transaction
            bool updateSuccess = await widget.eventService.markTicketAsUsed(
              ticketId: ticket.id,
              gatekeeperId: widget.gatekeeperId,
              euclideanDistance: distance,
            );

            // Log verification attempt
            await widget.eventService.logVerificationAttempt(
              ticketId: ticket.id,
              gatekeeperId: widget.gatekeeperId,
              eventId: widget.event.id,
              hashMatch: verificationResult['hashMatch'] as bool,
              euclideanDistance: distance,
              verificationStatus: updateSuccess ? 'verified' : 'verification_failed',
            );

            if (updateSuccess && mounted) {
              setState(() {
                _verificationStatus = 'success';
                _verificationMessage =
                    '✅ Entry Granted!\nName: ${ticket.attendeeName}\nDistance: ${distance.toStringAsFixed(4)}';
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
            }
          } else {
            // Face mismatch
            setState(() {
              _verificationStatus = 'failure';
              _verificationMessage =
                  '❌ Face Mismatch\nDistance: ${distance.toStringAsFixed(4)}\nEntry Denied';
              _statusMessage = 'Face does not match registered biometric';
            });

            // Log failed verification
            await widget.eventService.logVerificationAttempt(
              ticketId: ticket.id,
              gatekeeperId: widget.gatekeeperId,
              eventId: widget.event.id,
              hashMatch: false,
              euclideanDistance: distance,
              verificationStatus: 'verification_failed',
              errorMessage: 'Euclidean distance exceeded threshold',
            );

            // Stop camera for a moment
            await _cameraController?.stopImageStream();

            // Reset after delay
            await Future.delayed(const Duration(seconds: 2));
            if (mounted) {
              _resetVerification();
            }
          }
        } else {
          _stableFaceSince = null;
        }
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
      } finally {
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
      _statusMessage = 'Ready for next ticket';
      _stableFaceSince = null;
    });
    _tabController.animateTo(0);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
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
                  // Manual QR Input
                  TextField(
                    controller: _qrInputController,
                    decoration: InputDecoration(
                      labelText: 'Or enter Ticket ID manually',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check),
                        onPressed: () {
                          if (_qrInputController.text.isNotEmpty) {
                            _verifyTicket(_qrInputController.text);
                            _qrInputController.clear();
                          }
                        },
                      ),
                    ),
                    onSubmitted: (value) {
                      if (value.isNotEmpty) {
                        _verifyTicket(value);
                        _qrInputController.clear();
                      }
                    },
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
