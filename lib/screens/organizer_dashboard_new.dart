// ignore_for_file: prefer_const_constructors, use_build_context_synchronously

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import '../models/user.dart';
import '../models/event.dart';
import '../models/ticket.dart';
import '../services/auth_service.dart';
import '../services/enhanced_event_service.dart';
import 'create_event_screen.dart';
import 'face_verification_screen.dart';

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

  // QR scan state
  String? _scannedTicketId;
  bool _qrScanActive = false;
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _qrController;

  // Session log
  final List<Map<String, dynamic>> _sessionLog = [];

  @override
  void initState() {
    super.initState();
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

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      _qrController?.pauseCamera();
    }
    _qrController?.resumeCamera();
  }

  void _onQRViewCreated(QRViewController controller) {
    setState(() {
      _qrController = controller;
    });
    controller.resumeCamera();
    controller.scannedDataStream.listen((scanData) async {
      final code = scanData.code;
      if (code == null || code.isEmpty) return;
      await _qrController?.pauseCamera();
      if (mounted) {
        setState(() {
          _scannedTicketId = code;
          _qrScanActive = false;
        });
      }
    });
  }

  void _clearQR() {
    setState(() {
      _scannedTicketId = null;
      _qrScanActive = false;
    });
  }

  Future<void> _startVerification() async {
    if (_selectedEvent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an event first')),
      );
      return;
    }

    if (_scannedTicketId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please scan an attendee QR code first')),
      );
      return;
    }

    String ticketId = _scannedTicketId!;
    String? qrLandmarksJson;
    if (ticketId.contains('|')) {
      final parts = ticketId.split('|');
      ticketId = parts[0].trim();
      qrLandmarksJson = parts.length > 1 ? parts[1] : null;
    }

    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => FaceVerificationScreen(
          eventId: _selectedEvent!.id,
          organizerUid: widget.organizerUid,
          eventService: widget.eventService,
          targetTicketId: ticketId,
          qrLandmarksJson: qrLandmarksJson,
        ),
      ),
    );

    // Clear QR after verification attempt
    if (mounted) setState(() => _scannedTicketId = null);

    if (result is VerificationResult && result.granted) {
      if (mounted) {
        setState(() {
          _sessionLog.insert(0, {
            'name': result.attendeeName ?? 'Unknown',
            'ticketId': result.ticketId,
            'verifiedAt': DateTime.now(),
            'status': 'Access Granted',
            'match': result.matchPercentage,
          });
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Access granted to ${result.attendeeName}'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _qrController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEventSelector(),
          const Divider(height: 1),
          _buildQrSection(),
          const Divider(height: 1),
          _buildVerifyButton(),
          const Divider(height: 1),
          _buildVerificationLog(),
        ],
      ),
    );
  }

  Widget _buildVerifyButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 3 — Verify Identity',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_selectedEvent == null || _scannedTicketId == null) 
                  ? null 
                  : _startVerification,
              icon: const Icon(Icons.verified_user, color: Colors.white),
              label: const Text(
                'Start Face Verification',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                disabledBackgroundColor: Colors.grey,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 4,
              ),
            ),
          ),
          if (_selectedEvent != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Event: ${_selectedEvent!.name}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
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
              onChanged: (val) {
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

  Widget _buildQrSection() {
    return Container(
      color: Colors.deepPurple.shade50,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Step 2 — Scan Ticket QR',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.deepPurple,
                ),
              ),
              const Spacer(),
              if (_scannedTicketId != null)
                GestureDetector(
                  onTap: _clearQR,
                  child: const Icon(Icons.close, color: Colors.red, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_scannedTicketId != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'QR Scanned — Ticket: ${_scannedTicketId!.split('|')[0].length > 20 ? '${_scannedTicketId!.split('|')[0].substring(0, 20)}…' : _scannedTicketId!.split('|')[0]}',
                      style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: _clearQR,
                    child: const Text('Clear', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                ],
              ),
            )
          else if (_qrScanActive)
            SizedBox(
              height: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: QRView(
                  key: _qrKey,
                  onQRViewCreated: _onQRViewCreated,
                  overlay: QrScannerOverlayShape(
                    borderColor: Colors.deepPurple,
                    borderRadius: 10,
                    borderLength: 30,
                    borderWidth: 4,
                    cutOutSize: 160,
                  ),
                ),
              ),
            )
          else
            Text(
              'You MUST scan the QR code on the attendee\'s ticket before proceeding with face verification.',
              style: TextStyle(fontSize: 12, color: Colors.red[600], fontWeight: FontWeight.bold),
            ),
          const SizedBox(height: 8),
          if (_scannedTicketId == null && !_qrScanActive)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _qrScanActive = true),
                icon: const Icon(Icons.qr_code_scanner, color: Colors.deepPurple),
                label: const Text(
                  'Scan QR Code',
                  style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.deepPurple),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            )
          else if (_qrScanActive)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _qrScanActive = false),
                icon: const Icon(Icons.close, color: Colors.red),
                label: const Text(
                  'Cancel Scan',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
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
