import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event.dart';
import '../models/ticket.dart';

/// Enhanced Event Service with full CRUD, capacity management, and gatekeeper assignment
class EnhancedEventService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== EVENT CRUD OPERATIONS ====================

  /// Create a new event
  Future<String> createEvent({
    required String organizerId,
    required String name,
    required String description,
    required DateTime eventDate,
    required String location,
    required int capacity,
    required double ticketPrice,
  }) async {
    try {
      String eventId = _firestore.collection('events').doc().id;

      Event event = Event(
        id: eventId,
        name: name,
        description: description,
        eventDate: eventDate,
        location: location,
        organizerId: organizerId,
        capacity: capacity,
        ticketPrice: ticketPrice,
        createdAt: DateTime.now(),
      );

      await _firestore.collection('events').doc(eventId).set(event.toMap());
      return eventId;
    } catch (e) {
      rethrow;
    }
  }

  /// Get event by ID
  Future<Event?> getEventById(String eventId) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('events').doc(eventId).get();
      if (doc.exists) {
        return Event.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Get all events by organizer
  Future<List<Event>> getEventsByOrganizer(String organizerId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('events')
          .where('organizerId', isEqualTo: organizerId)
          .get();

      var events = snapshot.docs
          .map((doc) => Event.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
      events.sort((a, b) => a.eventDate.compareTo(b.eventDate));
      return events;
    } catch (e) {
      rethrow;
    }
  }

  /// Get all available events (for attendees to browse)
  Future<List<Event>> getAllAvailableEvents() async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('events')
          .where('eventDate', isGreaterThan: DateTime.now())
          .orderBy('eventDate', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => Event.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Update event details
  Future<void> updateEvent({
    required String eventId,
    String? name,
    String? description,
    DateTime? eventDate,
    String? location,
    int? capacity,
    double? ticketPrice,
  }) async {
    try {
      Map<String, dynamic> updateData = {};
      if (name != null) updateData['name'] = name;
      if (description != null) updateData['description'] = description;
      if (eventDate != null) updateData['eventDate'] = eventDate;
      if (location != null) updateData['location'] = location;
      if (capacity != null) updateData['capacity'] = capacity;
      if (ticketPrice != null) updateData['ticketPrice'] = ticketPrice;

      await _firestore.collection('events').doc(eventId).update(updateData);
    } catch (e) {
      rethrow;
    }
  }

  /// Delete event
  Future<void> deleteEvent(String eventId) async {
    try {
      // Delete all associated tickets
      QuerySnapshot ticketsSnapshot = await _firestore
          .collection('tickets')
          .where('eventId', isEqualTo: eventId)
          .get();

      for (var doc in ticketsSnapshot.docs) {
        await doc.reference.delete();
      }

      // Delete the event
      await _firestore.collection('events').doc(eventId).delete();
    } catch (e) {
      rethrow;
    }
  }

  // ==================== CAPACITY MANAGEMENT ====================

  /// Get number of tickets sold for an event
  Future<int> getTicketsSold(String eventId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('tickets')
          .where('eventId', isEqualTo: eventId)
          .get();

      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  /// Get number of tickets used (entries granted) for an event
  Future<int> getTicketsUsed(String eventId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('tickets')
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: 'USED')
          .get();

      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  /// Check if event has capacity available
  Future<bool> hasCapacityAvailable(String eventId) async {
    try {
      Event? event = await getEventById(eventId);
      if (event == null) return false;

      int ticketsSold = await getTicketsSold(eventId);
      return ticketsSold < event.capacity;
    } catch (e) {
      return false;
    }
  }

  /// Get event capacity status
  Future<Map<String, dynamic>> getCapacityStatus(String eventId) async {
    try {
      Event? event = await getEventById(eventId);
      if (event == null) {
        return {'error': 'Event not found'};
      }

      int sold = await getTicketsSold(eventId);
      int used = await getTicketsUsed(eventId);

      return {
        'eventId': eventId,
        'eventName': event.name,
        'capacity': event.capacity,
        'ticketsSold': sold,
        'ticketsUsed': used,
        'availableSlots': event.capacity - sold,
        'percentageFilled': ((sold / event.capacity) * 100).toStringAsFixed(1),
        'isFull': sold >= event.capacity,
      };
    } catch (e) {
      rethrow;
    }
  }

  // ==================== GATEKEEPER ASSIGNMENT ====================

  /// Assign a gatekeeper to an event by email
  Future<void> assignGatekeeper({
    required String eventId,
    required String gatekeeperEmail,
  }) async {
    try {
      // Verify the user exists in the system
      QuerySnapshot userSnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: gatekeeperEmail)
          .limit(1)
          .get();

      if (userSnapshot.docs.isEmpty) {
        throw Exception('User with email $gatekeeperEmail not found');
      }

      String gatekeeperId = userSnapshot.docs[0].id;

      // Update event with gatekeeper info
      await _firestore.collection('events').doc(eventId).update({
        'gatekeeperId': gatekeeperId,
        'gatekeeperEmail': gatekeeperEmail,
      });

      // Add gatekeeper permission record
      await _firestore
          .collection('gatekeeper_permissions')
          .doc('${eventId}_$gatekeeperId')
          .set({
            'eventId': eventId,
            'gatekeeperId': gatekeeperId,
            'gatekeeperEmail': gatekeeperEmail,
            'assignedAt': DateTime.now(),
            'status': 'active',
          });
    } catch (e) {
      rethrow;
    }
  }

  /// Remove gatekeeper from an event
  Future<void> removeGatekeeper(String eventId) async {
    try {
      Event? event = await getEventById(eventId);
      if (event == null) throw Exception('Event not found');

      // Remove from event
      await _firestore.collection('events').doc(eventId).update({
        'gatekeeperId': FieldValue.delete(),
        'gatekeeperEmail': FieldValue.delete(),
      });

      // Remove permission record if it exists
      if (event.gatekeeperId != null) {
        await _firestore
            .collection('gatekeeper_permissions')
            .doc('${eventId}_${event.gatekeeperId}')
            .delete();
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get gatekeeper's assigned events
  Future<List<Event>> getGatekeeperEvents(String gatekeeperId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('events')
          .where('gatekeeperId', isEqualTo: gatekeeperId)
          .get();

      return snapshot.docs
          .map((doc) => Event.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  // ==================== TICKET BOOKING ====================

  /// Book a ticket for an attendee (with capacity check)
  Future<String> bookTicket({
    required String eventId,
    required String attendeeId,
    required String attendeeName,
    required String attendeeEmail,
  }) async {
    try {
      // Check capacity
      Event? event = await getEventById(eventId);
      if (event == null) throw Exception('Event not found');

      bool hasCapacity = await hasCapacityAvailable(eventId);
      if (!hasCapacity) throw Exception('Event is at full capacity');

      // Check if attendee already has a ticket for this event
      Ticket? existingTicket = await getTicketByEventAndAttendee(eventId, attendeeId);
      if (existingTicket != null) {
        throw Exception('You already have a ticket for this event');
      }

      // Create new ticket
      String ticketId = _firestore.collection('tickets').doc().id;

      Ticket ticket = Ticket(
        id: ticketId,
        eventId: eventId,
        attendeeId: attendeeId,
        attendeeName: attendeeName,
        attendeeEmail: attendeeEmail,
        ticketPrice: event.ticketPrice,
        status: 'ACTIVE',
        createdAt: DateTime.now(),
      );

      await _firestore.collection('tickets').doc(ticketId).set(ticket.toMap());
      return ticketId;
    } catch (e) {
      rethrow;
    }
  }

  /// Get ticket by ID
  Future<Ticket?> getTicketById(String ticketId) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('tickets').doc(ticketId).get();
      if (doc.exists) {
        return Ticket.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Get ticket by event and attendee
  Future<Ticket?> getTicketByEventAndAttendee(String eventId, String attendeeId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('tickets')
          .where('eventId', isEqualTo: eventId)
          .where('attendeeId', isEqualTo: attendeeId)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return Ticket.fromMap(
          snapshot.docs[0].id,
          snapshot.docs[0].data() as Map<String, dynamic>,
        );
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Get all tickets for an attendee
  Future<List<Ticket>> getTicketsByAttendee(String attendeeId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('tickets')
          .where('attendeeId', isEqualTo: attendeeId)
          .get();

      var tickets = snapshot.docs
          .map((doc) => Ticket.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
      tickets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return tickets;
    } catch (e) {
      rethrow;
    }
  }

  /// Get all tickets for an event
  Future<List<Ticket>> getTicketsByEvent(String eventId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('tickets')
          .where('eventId', isEqualTo: eventId)
          .get();

      var tickets = snapshot.docs
          .map((doc) => Ticket.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
      tickets.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return tickets;
    } catch (e) {
      rethrow;
    }
  }

  // ==================== TICKET VERIFICATION ====================

  /// Update ticket with face biometric data
  Future<void> updateTicketWithBiometrics({
    required String ticketId,
    required String zkProof,
    required String? normalizedLandmarksEncrypted,
  }) async {
    try {
      await _firestore.collection('tickets').doc(ticketId).update({
        'zkProof': zkProof,
        'normalizedLandmarksEncrypted': normalizedLandmarksEncrypted,
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Mark ticket as USED (entry granted) - with atomic transaction to prevent double-entry
  Future<bool> markTicketAsUsed({
    required String ticketId,
    required String gatekeeperId,
    required double euclideanDistance,
  }) async {
    try {
      bool success = await _firestore.runTransaction<bool>((transaction) async {
        DocumentReference ticketRef = _firestore.collection('tickets').doc(ticketId);
        DocumentSnapshot snapshot = await transaction.get(ticketRef);

        if (!snapshot.exists) {
          throw Exception('Ticket not found');
        }

        Ticket ticket = Ticket.fromMap(ticketId, snapshot.data() as Map<String, dynamic>);

        // Double-check status is still ACTIVE
        if (ticket.status != 'ACTIVE') {
          throw Exception('Ticket is not active (status: ${ticket.status})');
        }

        // Atomic update
        transaction.update(ticketRef, {
          'status': 'USED',
          'entryTimestamp': DateTime.now(),
          'verifiedBy': gatekeeperId,
          'euclideanDistance': euclideanDistance,
        });

        return true;
      });

      return success;
    } catch (e) {
      return false;
    }
  }

  /// Cancel a ticket
  Future<void> cancelTicket(String ticketId) async {
    try {
      await _firestore.collection('tickets').doc(ticketId).update({
        'status': 'CANCELLED',
      });
    } catch (e) {
      rethrow;
    }
  }

  // ==================== AUDIT LOGGING ====================

  /// Log verification attempt to audit trail
  Future<void> logVerificationAttempt({
    required String ticketId,
    required String gatekeeperId,
    required String eventId,
    required bool hashMatch,
    required double euclideanDistance,
    required String verificationStatus,
    String? errorMessage,
  }) async {
    try {
      String auditId = _firestore.collection('verification_audit').doc().id;

      await _firestore.collection('verification_audit').doc(auditId).set({
        'auditId': auditId,
        'ticketId': ticketId,
        'gatekeeperId': gatekeeperId,
        'eventId': eventId,
        'timestamp': DateTime.now().toUtc(),
        'hashMatch': hashMatch,
        'euclideanDistance': euclideanDistance,
        'verificationStatus': verificationStatus,
        'errorMessage': errorMessage,
      });
    } catch (e) {
      // Log but don't fail the verification process
      // Warning: Failed to log verification attempt: $e
    }
  }

  // ==================== ANALYTICS ====================

  /// Get event statistics
  Future<Map<String, dynamic>> getEventStats(String eventId) async {
    try {
      Event? event = await getEventById(eventId);
      if (event == null) throw Exception('Event not found');

      int totalTickets = await getTicketsSold(eventId);
      int usedTickets = await getTicketsUsed(eventId);

      return {
        'eventId': eventId,
        'eventName': event.name,
        'eventDate': event.eventDate.toString(),
        'capacity': event.capacity,
        'ticketsSold': totalTickets,
        'ticketsUsed': usedTickets,
        'ticketsActive': totalTickets - usedTickets,
        'capacityPercentage': ((totalTickets / event.capacity) * 100).toStringAsFixed(1),
        'entryRate': totalTickets > 0 ? ((usedTickets / totalTickets) * 100).toStringAsFixed(1) : '0.0',
      };
    } catch (e) {
      rethrow;
    }
  }

  /// Stream event capacity updates in real-time
  Stream<Map<String, dynamic>> streamEventCapacity(String eventId) {
    return _firestore
        .collection('tickets')
        .where('eventId', isEqualTo: eventId)
        .snapshots()
        .asyncMap((_) async {
          return await getCapacityStatus(eventId);
        });
  }

  /// Stream ticket status in real-time
  Stream<Ticket?> streamTicket(String ticketId) {
    return _firestore
        .collection('tickets')
        .doc(ticketId)
        .snapshots()
        .map((snapshot) {
          if (snapshot.exists) {
            return Ticket.fromMap(ticketId, snapshot.data() as Map<String, dynamic>);
          }
          return null;
        });
  }

  /// Stream all verified (USED) tickets for an event in real-time
  Stream<List<Ticket>> streamVerifiedTicketsForEvent(String eventId) {
    return _firestore
        .collection('tickets')
        .where('eventId', isEqualTo: eventId)
        .where('status', isEqualTo: 'USED')
        .snapshots()
        .map((snapshot) {
          final tickets = snapshot.docs
              .map((doc) =>
                  Ticket.fromMap(doc.id, doc.data()))
              .toList();
          tickets.sort((a, b) {
            final aTime = a.entryTimestamp ?? a.createdAt;
            final bTime = b.entryTimestamp ?? b.createdAt;
            return bTime.compareTo(aTime);
          });
          return tickets;
        });
  }
}
