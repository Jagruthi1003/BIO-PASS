import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../models/event.dart';
import '../models/ticket.dart';
import '../models/user.dart';
import 'face_registration_screen.dart';

class AttendeeDashboard extends StatefulWidget {
  final User user;

  const AttendeeDashboard({super.key, required this.user});

  @override
  State<AttendeeDashboard> createState() => _AttendeeDashboardState();
}

class _AttendeeDashboardState extends State<AttendeeDashboard> {
  final AuthService _authService = AuthService();
  final EventService _eventService = EventService();
  User? _currentUser;
  List<Event> _events = [];
  List<Ticket> _registeredTickets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    try {
      final user = await _authService.getCurrentUser();
      if (mounted) {
        setState(() => _currentUser = user);

        if (user != null) {
          final events = await _eventService.getAllEvents();
          final tickets = await _eventService.getTicketsByAttendee(user.uid);

          if (mounted) {
            setState(() {
              _events = events;
              _registeredTickets = tickets;
              _isLoading = false;
            });
          }
        } else {
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/auth');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isEventRegistered(String eventId) {
    return _registeredTickets.any((ticket) => 
      ticket.eventId == eventId && ticket.isRegistered);
  }

  Ticket? _getEventTicket(String eventId) {
    try {
      return _registeredTickets.firstWhere(
        (ticket) => ticket.eventId == eventId && ticket.isRegistered,
      );
    } catch (e) {
      return null;
    }
  }

  void _registerForEvent(Event event) {
    if (_currentUser == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FaceRegistrationScreen(
          event: event,
          user: _currentUser!,
          onRegistrationComplete: () {
            _loadData();
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _logout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Attendee Dashboard'),
          backgroundColor: Colors.deepPurple,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendee Dashboard'),
        backgroundColor: Colors.deepPurple,
        elevation: 4,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                _currentUser?.name ?? 'User',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
          ),
        ],
      ),
      body: _events.isEmpty
          ? const Center(
              child: Text('No events available'),
            )
          : RefreshIndicator(
              onRefresh: () async => _loadData(),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _events.length,
                itemBuilder: (context, index) {
                  final event = _events[index];
                  final isRegistered = _isEventRegistered(event.id);
                  final ticket = _getEventTicket(event.id);

                  return _buildEventCard(event, isRegistered, ticket);
                },
              ),
            ),
    );
  }

  Widget _buildEventCard(Event event, bool isRegistered, Ticket? ticket) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event name
            Text(
              event.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 12),

            // Event details with icons
            _buildEventDetailRow(Icons.description, 'Description', event.description),
            _buildEventDetailRow(Icons.location_on, 'Location', event.location),
            _buildEventDetailRow(
              Icons.calendar_today,
              'Date',
              event.eventDate.toLocal().toString().split('.')[0],
            ),
            _buildEventDetailRow(Icons.people, 'Capacity', '${event.capacity}'),
            const SizedBox(height: 16),

            // Registration status and action buttons
            if (isRegistered && ticket != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Registered badge
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      border: Border.all(
                        color: Colors.green,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'REGISTERED',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            'Ticket: ${ticket.id}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildStatusBadge(_getStatusText(ticket), ticket),
                        if (ticket.isVerified) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.green,
                                width: 1,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified, color: Colors.green, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  'VERIFIED ✓',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (ticket.usedAt != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.blue,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle, color: Colors.blue, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  'Used: ${ticket.usedAt!.toLocal().toString().split('.')[0]}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _registerForEvent(event),
                  icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                  label: const Text(
                    'REGISTER WITH FACE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple.shade700,
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.deepPurple, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status, Ticket ticket) {
    Color bgColor;
    Color textColor;
    Color borderColor;

    switch (status) {
      case 'Verified':
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade900;
        borderColor = Colors.green;
        break;
      case 'Used':
        bgColor = Colors.blue.shade100;
        textColor = Colors.blue.shade900;
        borderColor = Colors.blue;
        break;
      default:
        bgColor = Colors.orange.shade100;
        textColor = Colors.orange.shade900;
        borderColor = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Text(
        'Status: ${status.toUpperCase()}',
        style: TextStyle(
          fontSize: 12,
          color: textColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getStatusText(Ticket ticket) {
    if (ticket.usedAt != null) {
      return 'Used';
    } else if (ticket.isVerified) {
      return 'Verified';
    } else if (ticket.isRegistered) {
      return 'Registered';
    } else {
      return 'Pending';
    }
  }
}
