import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ticket.dart';
import '../zk/zk_engine.dart';

class GatekeeperService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Ticket?> getTicketByIdForVerification(String ticketId) async {
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

  Future<List<Ticket>> getRegisteredTickets() async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('tickets')
          .where('isRegistered', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => Ticket.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> verifyAndMarkTicketUsed(String ticketId) async {
    try {
      await _firestore.collection('tickets').doc(ticketId).update({
        'isVerified': true,
        'usedAt': DateTime.now(),
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Verify face with ZK commitment
  Future<Map<String, dynamic>> verifyFaceWithZK(
    String ticketId,
    List<double> currentLandmarks,
  ) async {
    try {
      // Get ticket from Firestore
      DocumentSnapshot ticketDoc =
          await _firestore.collection('tickets').doc(ticketId).get();

      if (!ticketDoc.exists) {
        return {
          'success': false,
          'error': 'Ticket not found',
        };
      }

      final ticketData = ticketDoc.data() as Map<String, dynamic>;
      final ticket = Ticket.fromMap(ticketId, ticketData);

      // Check if ticket has face registration
      if (ticket.normalizedLandmarksEncrypted == null || ticket.normalizedLandmarksEncrypted!.isEmpty) {
        return {
          'success': false,
          'error': 'Ticket has not registered face for this event',
        };
      }

      // Decode Base64 securely-stored payload
      String decodedJson = utf8.decode(base64Decode(ticket.normalizedLandmarksEncrypted!));
      List<double> registeredLandmarks = List<double>.from(jsonDecode(decodedJson));

      // Verify using ZK engine
      final result = ZKEngine.getVerificationResult(
        currentLandmarks,
        registeredLandmarks,
      );

      return {
        'success': result['isVerified'] as bool,
        'similarity': result['similarity'],
        'similarityPercentage': result['similarityPercentage'],
        'message': result['message'],
        'threshold': result['threshold'],
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Verification error: $e',
      };
    }
  }

  /// Verify face against stored commitment (for privacy)
  Future<Map<String, dynamic>> verifyFaceCommitment(
    String ticketId,
    List<double> currentLandmarks,
  ) async {
    try {
      // Get ticket from Firestore
      DocumentSnapshot ticketDoc =
          await _firestore.collection('tickets').doc(ticketId).get();

      if (!ticketDoc.exists) {
        return {
          'success': false,
          'error': 'Ticket not found',
        };
      }

      final ticketData = ticketDoc.data() as Map<String, dynamic>;
      final ticket = Ticket.fromMap(ticketId, ticketData);

      if (ticket.zkProof == null) {
        return {
          'success': false,
          'error': 'No face commitment stored for this ticket',
        };
      }

      // Generate current proof and compare
      final currentProof = ZKEngine.generateProof(currentLandmarks);
      final isVerified = currentProof == ticket.zkProof;

      return {
        'success': isVerified,
        'message': isVerified ? 'Face verified' : 'Face does not match',
        'method': 'commitment',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Verification error: $e',
      };
    }
  }
}
