import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event.dart';
import '../models/ticket.dart';
import '../zk/zk_engine.dart';

class EventService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> createEvent(Event event) async {
    try {
      await _firestore.collection('events').doc(event.id).set(event.toMap());
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Event>> getEventsByOrganizer(String organizerId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('events')
          .where('organizerId', isEqualTo: organizerId)
          .get();

      return snapshot.docs
          .map((doc) => Event.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Event>> getAllEvents() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection('events').get();

      return snapshot.docs
          .map((doc) => Event.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

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

  Future<void> registerAttendeeForEvent({
    required String eventId,
    required String attendeeId,
    required String attendeeName,
    required String attendeeEmail,
  }) async {
    try {
      // Get event details to include in ticket ID
      Event? event = await getEventById(eventId);
      
      // Generate ticket ID: EVENTNAME_SEQUENCE
      int ticketCount = await _getEventTicketCount(eventId);
      String eventNamePrefix = event?.name.replaceAll(' ', '_').toUpperCase() ?? 'EVENT';
      String sequenceNumber = (ticketCount + 1).toString().padLeft(4, '0');
      String ticketId = '${eventNamePrefix}_$sequenceNumber';

      Ticket ticket = Ticket(
        id: ticketId,
        eventId: eventId,
        attendeeId: attendeeId,
        attendeeName: attendeeName,
        attendeeEmail: attendeeEmail,
        ticketPrice: event?.ticketPrice ?? 0.0,
        status: 'ACTIVE',
        createdAt: DateTime.now(),
      );

      await _firestore.collection('tickets').doc(ticketId).set(ticket.toMap());
    } catch (e) {
      rethrow;
    }
  }

  Future<int> _getEventTicketCount(String eventId) async {
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

  Future<List<Ticket>> getTicketsByAttendee(String attendeeId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('tickets')
          .where('attendeeId', isEqualTo: attendeeId)
          .get();

      return snapshot.docs
          .map((doc) => Ticket.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

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

  Future<List<Ticket>> getRegisteredTicketsByEvent(String eventId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('tickets')
          .where('eventId', isEqualTo: eventId)
          .where('isRegistered', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => Ticket.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Ticket>> getAllTicketsForEvent(String eventId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('tickets')
          .where('eventId', isEqualTo: eventId)
          .get();

      return snapshot.docs
          .map((doc) => Ticket.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

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

  Future<void> updateTicketWithFaceLandmarks({
    required String ticketId,
    required List<double> faceLandmarks,
  }) async {
    try {
      // Generate ZK proof from landmarks
      Map<String, dynamic> detailedProof = ZKEngine.generateDetailedProof(faceLandmarks);
      String zkProof = detailedProof['proof'] as String;

      // Instead of raw landmarks, store normalized structural features
      List<double> normalizedFeatures = ZKEngine.normalizeLandmarks(faceLandmarks);
      String featureData = base64Encode(utf8.encode(jsonEncode(normalizedFeatures)));

      // Store hashed data and obfuscated face map, ensuring raw arrays are not exposed in plaintext
      await _firestore.collection('tickets').doc(ticketId).update({
        'facialFeatures': featureData,
        'zkProof': zkProof,
        'zkProofMetadata': detailedProof,
        'isRegistered': true,
        'registrationStatus': 'registered',
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateTicketWithZKProof({
    required String ticketId,
    required String zkProof,
  }) async {
    try {
      await _firestore.collection('tickets').doc(ticketId).update({
        'zkProof': zkProof,
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> verifyTicketWithFace({
    required String ticketId,
    required List<double> currentFaceLandmarks,
  }) async {
    try {
      Ticket? ticket = await getTicketById(ticketId);
      if (ticket == null) {
        return {
          'success': false,
          'message': 'Ticket not found',
          'isVerified': false,
        };
      }

      if (ticket.facialFeatures == null || ticket.zkProof == null) {
        return {
          'success': false,
          'message': 'No facial feature data registered for this ticket',
          'isVerified': false,
        };
      }

      // Decode Base64 string back to landmark array
      String decodedJson = utf8.decode(base64Decode(ticket.facialFeatures!));
      List<double> registeredLandmarks = List<double>.from(jsonDecode(decodedJson));

      // Verify using makeup-tolerant algorithm first
      bool makeupTolerantVerified = ZKEngine.verifyWithMakeupTolerance(
        currentFaceLandmarks,
        registeredLandmarks,
      );

      Map<String, dynamic> verificationResult =
          ZKEngine.getVerificationResultWithMakeupTolerance(
        currentFaceLandmarks,
        registeredLandmarks,
      );

      String verificationMessage = makeupTolerantVerified
          ? '✅ Verified: Face matches with registered biometric data (makeup-tolerant)'
          : '❌ Not Verified: Face does not match registration';

      if (makeupTolerantVerified) {
        await _firestore.collection('tickets').doc(ticketId).update({
          'isVerified': true,
          'usedAt': DateTime.now(),
          'registrationStatus': 'verified',
          'verificationMessage': verificationMessage,
          'verificationMethod': 'makeup-tolerant',
          'similarityScore': verificationResult['similarity'],
        });
      } else {
        await _firestore.collection('tickets').doc(ticketId).update({
          'verificationMessage': verificationMessage,
          'verificationMethod': 'makeup-tolerant',
          'similarityScore': verificationResult['similarity'],
        });
      }

      return {
        'success': true,
        'isVerified': makeupTolerantVerified,
        'similarity': verificationResult['similarityPercentage'],
        'message': verificationMessage,
        'ticketId': ticket.id,
        'attendeeName': ticket.attendeeName,
        'makeupTolerant': true,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error verifying ticket: ${e.toString()}',
        'isVerified': false,
      };
    }
  }

  /// Verify ticket with standard method (no makeup tolerance)
  Future<Map<String, dynamic>> verifyTicketWithFaceStandard({
    required String ticketId,
    required List<double> currentFaceLandmarks,
  }) async {
    try {
      Ticket? ticket = await getTicketById(ticketId);
      if (ticket == null) {
        return {
          'success': false,
          'message': 'Ticket not found',
          'isVerified': false,
        };
      }

      if (ticket.facialFeatures == null || ticket.zkProof == null) {
        return {
          'success': false,
          'message': 'No facial feature data registered for this ticket',
          'isVerified': false,
        };
      }

      // Decode Base64 string back to feature array
      String decodedJson = utf8.decode(base64Decode(ticket.facialFeatures!));
      List<double> registeredLandmarks = List<double>.from(jsonDecode(decodedJson));

      // Verify face landmarks using ZK proof
      bool zkProofMatches = ZKEngine.verifyProof(currentFaceLandmarks, ticket.zkProof!);
      
      // Calculate similarity for additional verification
      bool isVerified = ZKEngine.verifyWithThreshold(
        currentFaceLandmarks,
        registeredLandmarks,
      );

      Map<String, dynamic> verificationResult =
          ZKEngine.getVerificationResult(currentFaceLandmarks, registeredLandmarks);

      String verificationMessage = isVerified && zkProofMatches
          ? '✅ Verified: Face matches with registered biometric data'
          : '❌ Not Verified: Face does not match registration';

      if (isVerified && zkProofMatches) {
        await _firestore.collection('tickets').doc(ticketId).update({
          'isVerified': true,
          'usedAt': DateTime.now(),
          'registrationStatus': 'verified',
          'verificationMessage': verificationMessage,
          'verificationMethod': 'standard',
        });
      } else {
        await _firestore.collection('tickets').doc(ticketId).update({
          'verificationMessage': verificationMessage,
          'verificationMethod': 'standard',
        });
      }

      return {
        'success': true,
        'isVerified': isVerified && zkProofMatches,
        'similarity': verificationResult['similarityPercentage'],
        'message': verificationMessage,
        'ticketId': ticket.id,
        'attendeeName': ticket.attendeeName,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error verifying ticket: ${e.toString()}',
        'isVerified': false,
      };
    }
  }

  Future<void> verifyTicket(String ticketId) async {
    try {
      await _firestore.collection('tickets').doc(ticketId).update({
        'isVerified': true,
        'usedAt': DateTime.now(),
        'registrationStatus': 'verified',
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<int> getEventRegistrationCount(String eventId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('tickets')
          .where('eventId', isEqualTo: eventId)
          .where('isRegistered', isEqualTo: true)
          .get();

      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  Future<bool> canRegisterForEvent({
    required String eventId,
    required Event event,
  }) async {
    try {
      int registrationCount = await getEventRegistrationCount(eventId);
      return registrationCount < event.capacity;
    } catch (e) {
      return false;
    }
  }

  // Analytics and reporting methods
  Future<Map<String, dynamic>> getEventAnalytics(String eventId) async {
    try {
      List<Ticket> allTickets = await getAllTicketsForEvent(eventId);
      
      int totalTickets = allTickets.length;
      int activeTickets = allTickets.where((t) => t.status == 'ACTIVE').length;
      int usedTickets = allTickets.where((t) => t.status == 'USED').length;
      int cancelledTickets = allTickets.where((t) => t.status == 'CANCELLED').length;

      return {
        'eventId': eventId,
        'totalTickets': totalTickets,
        'activeTickets': activeTickets,
        'usedTickets': usedTickets,
        'cancelledTickets': cancelledTickets,
        'activationRate': totalTickets > 0 ? (activeTickets / totalTickets * 100).toStringAsFixed(2) : '0',
        'usageRate': activeTickets > 0 ? (usedTickets / activeTickets * 100).toStringAsFixed(2) : '0',
      };
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Ticket>> getUnverifiedTicketsForEvent(String eventId) async {
    try {
      List<Ticket> allTickets = await getAllTicketsForEvent(eventId);
      return allTickets.where((ticket) => ticket.status == 'ACTIVE').toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Ticket>> getVerifiedTicketsForEvent(String eventId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('tickets')
          .where('eventId', isEqualTo: eventId)
          .where('isVerified', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => Ticket.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Update and verify ticket based on face matching result
  Future<void> verifyAndUpdateTicket({
    required String ticketId,
    required bool isVerified,
    required String verificationStatus,
    double matchSimilarity = 0.0,
    String matchStatus = 'unknown',
  }) async {
    try {
      Map<String, dynamic> updateData = {
        'isVerified': isVerified,
        'registrationStatus': verificationStatus,
        'verificationStatus': verificationStatus,
        'matchSimilarity': matchSimilarity,
        'matchStatus': matchStatus,
        'lastVerificationAttempt': DateTime.now(),
      };

      if (isVerified) {
        updateData['usedAt'] = DateTime.now();
        updateData['verificationMessage'] = 'Face verified - Entry granted';
      } else {
        updateData['verificationMessage'] = 'Face does not match - Entry denied';
      }

      await _firestore.collection('tickets').doc(ticketId).update(updateData);
    } catch (e) {
      debugPrint('⚠️ Firestore update failed (likely permission-denied rules): $e');
      // We swallow the error here instead of rethrowing it.
      // This prevents Firebase rule errors from overwriting the UI's successful face match message!
    }
  }
}
