// ignore_for_file: prefer_const_constructors, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';
import '../models/user.dart';
import '../models/event.dart';
import '../models/ticket.dart';
import '../services/auth_service.dart';
import '../services/enhanced_event_service.dart';
import '../services/face_biometric_service.dart';
import 'create_event_screen.dart';

class OrganizerDashboardNew extends StatefulWidget {
  final User user;

  const OrganizerDashboardNew({super.key, required this.user});

  @override
  State<OrganizerDashboardNew> createState() => _OrganizerDashboardNewState();
}

class _OrganizerDashboardNewState extends State<OrganizerDashboardNew>
    with SingleTickerProviderStateMixin {
  final EnhancedEventService _eventService = EnhancedEventService();
  final AuthService _authService = AuthService();
  late TabController _tabController;
  late Future<List<Event>> _eventsFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refreshEvents();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshEvents() {
    setState(() {
      _eventsFuture = _eventService.getEventsByOrganizer(widget.user.uid);
    });
  }

  void _logout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizer Dashboard'),
        backgroundColor: Colors.deepPurple,
        elevation: 4,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                widget.user.name,
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.event), text: 'My Events'),
            Tab(icon: Icon(Icons.verified_user), text: 'Verification'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEventsTab(),
          OrganizerVerificationTab(
            organizerUid: widget.user.uid,
            eventService: _eventService,
          ),
        ],
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _tabController,
        builder: (context, _) {
          if (_tabController.index != 0) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            backgroundColor: Colors.deepPurple,
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreateEventScreen(
                    organizerId: widget.user.uid,
                    onEventCreated: _refreshEvents,
                  ),
                ),
              );
              if (result == true) _refreshEvents();
            },
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'New Event',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEventsTab() {
    return FutureBuilder<List<Event>>(
      future: _eventsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final events = snapshot.data ?? [];

        if (events.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event, size: 72, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No events yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap "New Event" to create your first event',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _refreshEvents(),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: events.length,
            itemBuilder: (context, index) {
              return _OrganizerEventCard(
                event: events[index],
                eventService: _eventService,
                organizerId: widget.user.uid,
                onRefresh: _refreshEvents,
              );
            },
          ),
        );
      },
    );
  }
}

// ===== EVENT CARD FOR ORGANIZER =====

class _OrganizerEventCard extends StatelessWidget {
  final Event event;
  final EnhancedEventService eventService;
  final String organizerId;
  final VoidCallback onRefresh;

  const _OrganizerEventCard({
    required this.event,
    required this.eventService,
    required this.organizerId,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
                // Edit Button
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.deepPurple),
                  tooltip: 'Edit Event',
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreateEventScreen(
                          organizerId: organizerId,
                          onEventCreated: onRefresh,
                          existingEvent: event,
                        ),
                      ),
                    );
                    if (result == true) onRefresh();
                  },
                ),
                // Delete Button
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Delete Event',
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete Event'),
                        content: Text(
                          'Are you sure you want to delete "${event.name}"? This will also delete all registered tickets.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      try {
                        await eventService.deleteEvent(event.id);
                        onRefresh();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Event deleted')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            _detailRow(Icons.description, event.description),
            _detailRow(Icons.location_on, event.location),
            _detailRow(
              Icons.calendar_today,
              event.eventDate.toLocal().toString().split('.')[0],
            ),
            _detailRow(Icons.people, 'Capacity: ${event.capacity}'),
            _detailRow(
              Icons.attach_money,
              event.ticketPrice == 0
                  ? 'Free'
                  : '\$${event.ticketPrice.toStringAsFixed(2)}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.deepPurple.shade300),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ===== VERIFICATION TAB =====

class OrganizerVerificationTab extends StatefulWidget {
  final String organizerUid;
  final EnhancedEventService eventService;

  const OrganizerVerificationTab({
    super.key,
    required this.organizerUid,
    required this.eventService,
  });

  @override
  State<OrganizerVerificationTab> createState() =>
      _OrganizerVerificationTabState();
}

class _OrganizerVerificationTabState extends State<OrganizerVerificationTab> {
  Event? _selectedEvent;
  List<Event> _events = [];
  bool _eventsLoading = true;

  // Camera / face detection
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _cameraActive = false;
  bool _isProcessing = false;
  String _statusMessage = 'Select an event and start the camera to begin';
  DateTime? _stableFaceSince;

  // Verification state
  String _verificationStatus = ''; // 'success' | 'failure' | ''
  String _matchedAttendeeName = '';

  // Log of verified attendees (for current session, plus Firestore stream)
  final List<Map<String, dynamic>> _sessionLog = [];

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(options: FaceDetectorOptions());
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    try {
      final events =
          await widget.eventService.getEventsByOrganizer(widget.organizerUid);
      if (mounted) {
        setState(() {
          _events = events;
          _eventsLoading = false;
          if (events.length == 1) _selectedEvent = events[0];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _eventsLoading = false);
    }
  }

  Future<void> _startCamera() async {
    if (_selectedEvent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an event first')),
      );
      return;
    }
    try {
      final cameras = await availableCameras();
      // Prefer front camera for verification; fall back to rear
      CameraDescription cam;
      try {
        cam = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
        );
      } catch (_) {
        cam = cameras.first;
      }

      _cameraController = CameraController(
        cam,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() {
        _cameraActive = true;
        _statusMessage = 'Camera ready — position face in front of camera';
        _verificationStatus = '';
      });

      _startFaceStream();
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Camera error: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  void _startFaceStream() {
    _cameraController?.startImageStream((image) async {
      if (_isProcessing || _verificationStatus == 'success') return;

      try {
        final inputImage = InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.nv21,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );

        final faces = await _faceDetector!.processImage(inputImage);

        if (faces.isEmpty) {
          _stableFaceSince = null;
          if (mounted) {
            setState(() => _statusMessage = 'No face detected — look at camera');
          }
          return;
        }

        final now = DateTime.now();
        _stableFaceSince ??= now;
        final stableMs = now.difference(_stableFaceSince!).inMilliseconds;

        if (stableMs < 1500) {
          if (mounted) {
            setState(() {
              _statusMessage =
                  'Hold still… ${(1.5 - stableMs / 1000).toStringAsFixed(1)}s';
            });
          }
          return;
        }

        _isProcessing = true;
        if (mounted) {
          setState(() => _statusMessage = 'Scanning face against registered attendees…');
        }

        // Extract live landmarks
        final liveLandmarks =
            FaceBiometricService.extractAndNormalizeLandmarks(faces.first);

        // Fetch all ACTIVE tickets for this event
        final tickets =
            await widget.eventService.getTicketsByEvent(_selectedEvent!.id);
        final activeTickets =
            tickets.where((t) => t.status == 'ACTIVE').toList();

        if (activeTickets.isEmpty) {
          if (mounted) {
            setState(() {
              _verificationStatus = 'failure';
              _statusMessage = 'No active registrations found';
            });
          }
          _isProcessing = false;
          return;
        }

        // Compare against each stored face
        Ticket? matchedTicket;
        double bestDistance = double.infinity;

        for (final ticket in activeTickets) {
          if (ticket.normalizedLandmarksEncrypted == null) continue;

          try {
            final storedLandmarks =
                FaceBiometricService.decryptNormalizedLandmarks(
              ticket.normalizedLandmarksEncrypted!,
              ticket.id,
            );

            final distance = FaceBiometricService.calculateEuclideanDistance(
              liveLandmarks,
              storedLandmarks,
            );

            if (distance < bestDistance) {
              bestDistance = distance;
              if (distance <= 0.6) {
                matchedTicket = ticket;
              }
            }
          } catch (_) {
            // Decryption error for this ticket — skip it
          }
        }

        if (matchedTicket != null) {
          // Match found — grant access
          await _cameraController?.stopImageStream();

          final updateSuccess = await widget.eventService.markTicketAsUsed(
            ticketId: matchedTicket.id,
            gatekeeperId: widget.organizerUid,
            euclideanDistance: bestDistance,
          );

          await widget.eventService.logVerificationAttempt(
            ticketId: matchedTicket.id,
            gatekeeperId: widget.organizerUid,
            eventId: _selectedEvent!.id,
            hashMatch: true,
            euclideanDistance: bestDistance,
            verificationStatus: updateSuccess ? 'verified' : 'already_used',
          );

          final now2 = DateTime.now();
          if (mounted) {
            setState(() {
              _verificationStatus = 'success';
              _matchedAttendeeName = matchedTicket!.attendeeName;
              _statusMessage = 'Entry granted!';
              _sessionLog.insert(0, {
                'name': matchedTicket.attendeeName,
                'email': matchedTicket.attendeeEmail,
                'registeredAt': matchedTicket.createdAt,
                'verifiedAt': now2,
                'status': 'Access Granted',
                'distance': bestDistance,
              });
            });
          }

          await Future.delayed(const Duration(seconds: 3));
          if (mounted) {
            setState(() {
              _verificationStatus = '';
              _stableFaceSince = null;
              _statusMessage = 'Ready — position next face';
            });
            _startFaceStream();
          }
        } else {
          // No match
          await _cameraController?.stopImageStream();

          if (mounted) {
            setState(() {
              _verificationStatus = 'failure';
              _statusMessage = 'No matching registration found';
            });
          }

          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            setState(() {
              _verificationStatus = '';
              _stableFaceSince = null;
              _statusMessage = 'Ready — position next face';
            });
            _startFaceStream();
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _statusMessage = 'Error: $e');
        }
      } finally {
        _isProcessing = false;
      }
    });
  }

  void _stopCamera() async {
    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();
    _cameraController = null;
    if (mounted) {
      setState(() {
        _cameraActive = false;
        _statusMessage = 'Camera stopped';
        _verificationStatus = '';
        _stableFaceSince = null;
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Event Selector ---
          _buildEventSelector(),
          const Divider(height: 1),
          // --- Camera Section ---
          _buildCameraSection(),
          const Divider(height: 1),
          // --- Log Table ---
          _buildVerificationLog(),
        ],
      ),
    );
  }

  Widget _buildEventSelector() {
    return Container(
      color: Colors.deepPurple.shade50,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 1 — Select Event',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 8),
          if (_eventsLoading)
            const CircularProgressIndicator()
          else if (_events.isEmpty)
            const Text(
              'No events found. Create an event first.',
              style: TextStyle(color: Colors.grey),
            )
          else
            DropdownButtonFormField<Event>(
              initialValue: _selectedEvent,
              hint: const Text('Choose an event'),
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.deepPurple),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: _events
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(
                        '${e.name}  •  ${e.eventDate.toLocal().toString().split('.')[0]}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _cameraActive
                  ? null
                  : (val) {
                      setState(() {
                        _selectedEvent = val;
                        _sessionLog.clear();
                      });
                    },
            ),
        ],
      ),
    );
  }

  Widget _buildCameraSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 2 — Face Scan',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 12),
          if (_cameraActive && _cameraController != null &&
              _cameraController!.value.isInitialized)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 300,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(_cameraController!),
                    // Face Guide Oval
                    Center(
                      child: CustomPaint(
                        size: const Size(double.infinity, 300),
                        painter: _FaceOvalPainter(),
                      ),
                    ),
                    // Result Overlay
                    if (_verificationStatus.isNotEmpty)
                      Container(
                        color: Colors.black54,
                        child: Center(
                          child: Container(
                            margin: const EdgeInsets.all(24),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: _verificationStatus == 'success'
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
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
                                  size: 56,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _verificationStatus == 'success'
                                      ? '✅ Match Found'
                                      : '❌ No Match',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _verificationStatus == 'success'
                                      ? 'Access Granted\n$_matchedAttendeeName'
                                      : 'Access Denied',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // Status Bar
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Text(
                          _statusMessage,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.face, size: 56, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text(
                    'Camera not active',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statusMessage,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _cameraActive ? null : _startCamera,
                  icon: const Icon(Icons.videocam, color: Colors.white),
                  label: const Text(
                    'Start Camera',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    disabledBackgroundColor: Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (_cameraActive) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _stopCamera,
                    icon: const Icon(Icons.videocam_off, color: Colors.red),
                    label: const Text(
                      'Stop Camera',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationLog() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.list_alt, color: Colors.deepPurple, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Verification Log',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.deepPurple,
                ),
              ),
              if (_selectedEvent != null) ...[
                const Spacer(),
                // Live count from Firestore
                StreamBuilder<List<Ticket>>(
                  stream: widget.eventService
                      .streamVerifiedTicketsForEvent(_selectedEvent!.id),
                  builder: (context, snap) {
                    final count = snap.data?.length ?? 0;
                    return Text(
                      '$count verified',
                      style:
                          const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (_selectedEvent == null)
            const Text(
              'Select an event to see the verification log',
              style: TextStyle(color: Colors.grey),
            )
          else
            StreamBuilder<List<Ticket>>(
              stream: widget.eventService
                  .streamVerifiedTicketsForEvent(_selectedEvent!.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final verified = snapshot.data ?? [];
                if (verified.isEmpty && _sessionLog.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: Text(
                      'No verified attendees yet',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  );
                }

                // Combine Firestore verified tickets
                return Column(
                  children: [
                    // Table header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text('Attendee',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text('Registered',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text('Verified At',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text('Status',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...verified.map(
                      (ticket) => _LogRow(
                        name: ticket.attendeeName,
                        registeredAt: ticket.createdAt,
                        verifiedAt: ticket.entryTimestamp,
                        status: 'Granted',
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final String name;
  final DateTime registeredAt;
  final DateTime? verifiedAt;
  final String status;

  const _LogRow({
    required this.name,
    required this.registeredAt,
    required this.verifiedAt,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _fmt(registeredAt),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              verifiedAt != null ? _fmt(verifiedAt!) : '—',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                status,
                style: const TextStyle(
                    color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}\n${dt.day}/${dt.month}/${dt.year}';
}

class _FaceOvalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.deepPurple.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final w = size.width * 0.55;
    final h = size.height * 0.75;
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;
    canvas.drawOval(Rect.fromLTWH(left, top, w, h), paint);
  }

  @override
  bool shouldRepaint(_FaceOvalPainter old) => false;
}
