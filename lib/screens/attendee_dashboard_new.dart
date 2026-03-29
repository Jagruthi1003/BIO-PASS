// ignore_for_file: use_build_context_synchronously, prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import '../models/user.dart';
import '../models/event.dart';
import '../models/ticket.dart';
import '../services/enhanced_event_service.dart';
import '../services/local_storage_service.dart';
import '../services/auth_service.dart';
import 'gatekeeper_verification_screen.dart';
import 'zk_face_registration_screen_new.dart';

class AttendeeDashboardNew extends StatefulWidget {
  final User user;

  const AttendeeDashboardNew({super.key, required this.user});

  @override
  State<AttendeeDashboardNew> createState() => _AttendeeDashboardNewState();
}

class _AttendeeDashboardNewState extends State<AttendeeDashboardNew>
    with SingleTickerProviderStateMixin {
  final EnhancedEventService _eventService = EnhancedEventService();
  final AuthService _authService = AuthService();
  late TabController _tabController;
  late Future<List<Event>> _gatekeeperEventsFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _gatekeeperEventsFuture = _eventService.getGatekeeperEvents(widget.user.uid);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendee Dashboard',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepPurple,
        elevation: 4,
        actions: [
          FutureBuilder<List<Event>>(
            future: _gatekeeperEventsFuture,
            builder: (context, snapshot) {
              final events = snapshot.data ?? const <Event>[];
              if (events.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: 'Gatekeeper Mode',
                icon: const Icon(Icons.verified_user),
                onPressed: () => _showGatekeeperEventPicker(events),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Text(
                widget.user.name,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _authService.logout();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/auth');
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Welcome Section with deepPurple gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade400],
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${widget.user.name} !',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Browse events and manage your tickets',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          // Tabs
          TabBar(
            controller: _tabController,
            labelColor: Colors.deepPurple,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.deepPurple,
            tabs: const [
              Tab(text: 'Browse Events'),
              Tab(text: 'My Tickets'),
            ],
          ),
          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Browse Events Tab
                _buildBrowseEventsTab(),
                // My Tickets Tab
                _buildMyTicketsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowseEventsTab() {
    return FutureBuilder<List<Event>>(
      future: _eventService.getAllAvailableEvents(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        List<Event> events = snapshot.data ?? [];

        if (events.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No events available',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              Event event = events[index];
              return EventBrowseCard(
                event: event,
                attendeeId: widget.user.uid,
                attendeeName: widget.user.name,
                attendeeEmail: widget.user.email,
                eventService: _eventService,
                onBookingSuccess: () {
                  setState(() {});
                  _tabController.animateTo(1);
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMyTicketsTab() {
    return FutureBuilder<List<Ticket>>(
      future: _eventService.getTicketsByAttendee(widget.user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        List<Ticket> tickets = snapshot.data ?? [];

        if (tickets.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.confirmation_number, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No tickets booked yet',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _tabController.animateTo(0),
                  child: const Text('Browse Events'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: ListView.builder(
            itemCount: tickets.length,
            itemBuilder: (context, index) {
              Ticket ticket = tickets[index];
              return MyTicketCard(
                ticket: ticket,
                eventService: _eventService,
                onStatusChange: () {
                  setState(() {});
                },
              );
            },
          ),
        );
      },
    );
  }

  void _showGatekeeperEventPicker(List<Event> events) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return ListTile(
                leading: const Icon(Icons.event_available),
                title: Text(event.name),
                subtitle: Text(event.location),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GatekeeperVerificationScreen(
                        event: event,
                        gatekeeperId: widget.user.uid,
                        eventService: _eventService,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class EventBrowseCard extends StatefulWidget {
  final Event event;
  final String attendeeId;
  final String attendeeName;
  final String attendeeEmail;
  final EnhancedEventService eventService;
  final VoidCallback onBookingSuccess;

  const EventBrowseCard({
    super.key,
    required this.event,
    required this.attendeeId,
    required this.attendeeName,
    required this.attendeeEmail,
    required this.eventService,
    required this.onBookingSuccess,
  });

  @override
  State<EventBrowseCard> createState() => _EventBrowseCardState();
}

class _EventBrowseCardState extends State<EventBrowseCard> {
  late Future<Map<String, dynamic>> _capacityFuture;
  late Future<Ticket?> _existingTicketFuture;

  @override
  void initState() {
    super.initState();
    _capacityFuture = widget.eventService.getCapacityStatus(widget.event.id);
    _existingTicketFuture = widget.eventService.getTicketByEventAndAttendee(
      widget.event.id,
      widget.attendeeId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event Header
            Text(
              widget.event.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              widget.event.description,
              style: TextStyle(color: Colors.grey[600]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            // Details
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.event.eventDate.toString().split('.')[0],
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.event.location,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.attach_money, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  '\$${widget.event.ticketPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Capacity Status
            FutureBuilder<Map<String, dynamic>>(
              future: _capacityFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 8,
                    child: LinearProgressIndicator(),
                  );
                }

                Map<String, dynamic> capacity = snapshot.data ?? {};
                bool isFull = capacity['isFull'] ?? false;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Availability',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          '${capacity['availableSlots'] ?? 0} of ${capacity['capacity'] ?? 0} available',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ((capacity['ticketsSold'] ?? 0) /
                            (capacity['capacity'] ?? 1)),
                        minHeight: 6,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isFull ? Colors.red : Colors.green,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // Book/Already Booked Button
            FutureBuilder<Ticket?>(
              future: _existingTicketFuture,
              builder: (context, snapshot) {
                bool hasTicket = snapshot.data != null;

                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: hasTicket
                        ? null
                        : () async {
                            _showBookingConfirmation();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          hasTicket ? Colors.grey : Colors.deepPurple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      hasTicket ? '✓ Already Booked' : 'Book Ticket',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBookingConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Event: ${widget.event.name}'),
            const SizedBox(height: 8),
            Text('Price: \$${widget.event.ticketPrice.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            const Text(
              'You will be asked to register your face for biometric verification at event entry.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _bookTicket();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _bookTicket() async {
    try {
      String ticketId = await widget.eventService.bookTicket(
        eventId: widget.event.id,
        attendeeId: widget.attendeeId,
        attendeeName: widget.attendeeName,
        attendeeEmail: widget.attendeeEmail,
      );

      if (!mounted) return;

      // Navigate to face registration screen
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ZkFaceRegistrationScreenNew(
            ticketId: ticketId,
            eventId: widget.event.id,
            eventService: widget.eventService,
          ),
        ),
      );

      if (result == true && mounted) {
        widget.onBookingSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ticket booked successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class MyTicketCard extends StatefulWidget {
  final Ticket ticket;
  final EnhancedEventService eventService;
  final VoidCallback onStatusChange;

  const MyTicketCard({
    super.key,
    required this.ticket,
    required this.eventService,
    required this.onStatusChange,
  });

  @override
  State<MyTicketCard> createState() => _MyTicketCardState();
}

class _MyTicketCardState extends State<MyTicketCard> {
  late Stream<Ticket?> _ticketStream;

  @override
  void initState() {
    super.initState();
    _ticketStream = widget.eventService.streamTicket(widget.ticket.id);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Ticket?>(
      stream: _ticketStream,
      initialData: widget.ticket,
      builder: (context, snapshot) {
        Ticket ticket = snapshot.data ?? widget.ticket;

        Color statusColor;
        String statusEmoji;
        String statusText;

        switch (ticket.status) {
          case 'ACTIVE':
            statusColor = Colors.green;
            statusEmoji = '🟢';
            statusText = 'ACTIVE - Ready for Entry';
            break;
          case 'USED':
            statusColor = Colors.blue;
            statusEmoji = '✅';
            statusText = 'USED - Entry Granted';
            break;
          case 'CANCELLED':
            statusColor = Colors.red;
            statusEmoji = '🔴';
            statusText = 'CANCELLED';
            break;
          default:
            statusColor = Colors.grey;
            statusEmoji = '❓';
            statusText = ticket.status;
        }

        return Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ticket ID and Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ticket ID: ${ticket.id}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Event ID: ${ticket.eventId}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusEmoji,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Status Details
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      if (ticket.entryTimestamp != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Entry Time: ${ticket.entryTimestamp}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                      if (ticket.euclideanDistance != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Verification Distance: ${ticket.euclideanDistance?.toStringAsFixed(4)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // QR Code Display
                if (ticket.status == 'ACTIVE') ...[
                  Center(
                    child: QrCodeDisplay(
                      ticketId: ticket.id,
                      eventId: ticket.eventId,
                      attendeeId: ticket.attendeeId,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Price
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Price:'),
                    Text(
                      '\$${ticket.ticketPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class QrCodeDisplay extends StatelessWidget {
  final String ticketId;
  final String eventId;
  final String attendeeId;

  const QrCodeDisplay({
    super.key,
    required this.ticketId,
    required this.eventId,
    required this.attendeeId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<double>?>(
      future: LocalStorageService.getFacialFeatures(ticketId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final features = snapshot.data;
        String qrPayload = ticketId;
        if (features != null) {
          qrPayload = '$ticketId|${jsonEncode(features)}';
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Text(
                    'Show this QR code at the gate',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  QrImageView(
                    data: qrPayload,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
