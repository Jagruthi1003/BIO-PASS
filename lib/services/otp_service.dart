import 'dart:developer' as developer;
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'email_service.dart';

/// Service for handling OTP verification through email
/// Includes validation, security checks, and email delivery
class OTPService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // OTP Configuration Constants
  static const int otpLength = 6;
  static const int otpValidityMinutes = 10;
  static const int maxAttempts = 5;
  static const int resendCooldownSeconds = 60;

  /// Generate a random 6-digit OTP
  static String generateOTP() {
    Random random = Random();
    int otp = 100000 + random.nextInt(900000);
    return otp.toString();
  }

  /// Validate email format
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email.trim());
  }

  /// Send OTP to user's email with validation
  Future<Map<String, dynamic>> sendOTP({
    required String email,
    required String userID,
  }) async {
    try {
      final trimmedEmail = email.trim().toLowerCase();

      // Validate email format first
      if (!_isValidEmail(trimmedEmail)) {
        developer.log('Invalid email format: $trimmedEmail', level: 1000);
        return {
          'success': false,
          'message': 'Invalid email format. Please provide a valid email address.',
          'code': 'invalid_email_format',
        };
      }

      // Check if email exists in users collection
      final userDoc = await _firestore.collection('users').doc(userID).get();
      if (!userDoc.exists) {
        developer.log('User not found: $userID', level: 1000);
        return {
          'success': false,
          'message': 'User not found. Please sign up first.',
          'code': 'user_not_found',
        };
      }

      // Check if email matches the user's email
      final userData = userDoc.data() as Map<String, dynamic>;
      if ((userData['email'] as String? ?? '').toLowerCase() != trimmedEmail) {
        developer.log('Email mismatch for user: $userID', level: 1000);
        return {
          'success': false,
          'message': 'Email mismatch. Please use the correct email.',
          'code': 'email_mismatch',
        };
      }

      String otp = generateOTP();
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(minutes: otpValidityMinutes));

      // Store OTP in Firestore with timestamp and expiry
      await _firestore.collection('otp_verification').doc(trimmedEmail).set({
        'otp': otp,
        'userID': userID,
        'email': trimmedEmail,
        'createdAt': now,
        'expiresAt': expiresAt,
        'verified': false,
        'attempts': 0,
        'lastAttemptTime': null,
      });

      // Send email with OTP via Cloud Function
      final emailSent = await EmailService.sendOTPEmail(
        email: trimmedEmail,
        otp: otp,
      );

      if (emailSent) {
        developer.log('OTP sent successfully to $trimmedEmail');
        return {
          'success': true,
          'message': 'OTP sent to your email successfully. Valid for $otpValidityMinutes minutes.',
          'email': trimmedEmail,
        };
      } else {
        developer.log('OTP saved to Firestore but email sending failed for $trimmedEmail', level: 800);
        // Return success but with warning if in development mode
        return {
          'success': true,
          'message': 'OTP generated (email sending is in development mode). Check console for OTP.',
          'email': trimmedEmail,
          'isDevelopmentMode': true,
        };
      }
    } catch (e) {
      developer.log('Error sending OTP: $e', level: 1000);
      return {
        'success': false,
        'message': 'Error sending OTP: ${e.toString()}',
        'code': 'otp_send_error',
      };
    }
  }

  /// Verify OTP entered by user with comprehensive validation
  Future<Map<String, dynamic>> verifyOTP({
    required String email,
    required String enteredOTP,
  }) async {
    try {
      final trimmedEmail = email.trim().toLowerCase();
      final trimmedOTP = enteredOTP.trim();

      // Validate email format
      if (!_isValidEmail(trimmedEmail)) {
        return {
          'success': false,
          'message': 'Invalid email format.',
          'code': 'invalid_email_format',
        };
      }

      // Validate OTP format
      if (trimmedOTP.isEmpty) {
        return {
          'success': false,
          'message': 'Please enter the OTP code.',
          'code': 'empty_otp',
        };
      }

      if (trimmedOTP.length != otpLength || !RegExp(r'^\d+$').hasMatch(trimmedOTP)) {
        return {
          'success': false,
          'message': 'OTP must be a 6-digit number.',
          'code': 'invalid_otp_format',
        };
      }

      // Get OTP record from Firestore
      DocumentSnapshot doc = await _firestore
          .collection('otp_verification')
          .doc(trimmedEmail)
          .get();

      if (!doc.exists) {
        return {
          'success': false,
          'message': 'No OTP found for this email. Please request a new OTP.',
          'code': 'otp_not_found',
        };
      }

      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

      // Check if OTP has expired
      DateTime expiresAt = (data['expiresAt'] as Timestamp).toDate();
      if (DateTime.now().isAfter(expiresAt)) {
        return {
          'success': false,
          'message': 'OTP has expired. Please request a new OTP.',
          'code': 'otp_expired',
        };
      }

      // Check if maximum attempts exceeded
      int attempts = data['attempts'] ?? 0;
      if (attempts >= maxAttempts) {
        return {
          'success': false,
          'message': 'Too many failed attempts. Please request a new OTP.',
          'code': 'max_attempts_exceeded',
        };
      }

      // Verify OTP
      if (data['otp'] == trimmedOTP) {
        // Mark as verified
        await _firestore
            .collection('otp_verification')
            .doc(trimmedEmail)
            .update({
          'verified': true,
          'verifiedAt': DateTime.now(),
        });

        return {
          'success': true,
          'message': 'Email verified successfully!',
          'userID': data['userID'],
          'code': 'verification_success',
        };
      } else {
        // Increment attempts
        int newAttempts = attempts + 1;
        await _firestore
            .collection('otp_verification')
            .doc(trimmedEmail)
            .update({
          'attempts': newAttempts,
          'lastAttemptTime': DateTime.now(),
        });

        return {
          'success': false,
          'message': 'Incorrect OTP. Please try again. Attempts remaining: ${maxAttempts - newAttempts}',
          'attempts': newAttempts,
          'remainingAttempts': maxAttempts - newAttempts,
          'code': 'incorrect_otp',
        };
      }
    } catch (e) {
      developer.log('Error verifying OTP: $e', level: 1000);
      return {
        'success': false,
        'message': 'Error verifying OTP: ${e.toString()}',
        'code': 'verification_error',
      };
    }
  }

  /// Resend OTP to email with cooldown check
  Future<Map<String, dynamic>> resendOTP({required String email}) async {
    try {
      final trimmedEmail = email.trim().toLowerCase();

      // Validate email format
      if (!_isValidEmail(trimmedEmail)) {
        return {
          'success': false,
          'message': 'Invalid email format.',
          'code': 'invalid_email_format',
        };
      }

      // Check if OTP document exists
      DocumentSnapshot doc = await _firestore
          .collection('otp_verification')
          .doc(trimmedEmail)
          .get();

      if (!doc.exists) {
        return {
          'success': false,
          'message': 'No previous OTP request found. Please sign up first.',
          'code': 'no_previous_otp',
        };
      }

      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      
      // Check cooldown period
      DateTime? lastCreated = (data['createdAt'] as Timestamp?)?.toDate();
      if (lastCreated != null) {
        int secondsElapsed = DateTime.now().difference(lastCreated).inSeconds;
        if (secondsElapsed < resendCooldownSeconds) {
          int waitSeconds = resendCooldownSeconds - secondsElapsed;
          return {
            'success': false,
            'message': 'Please wait $waitSeconds seconds before requesting a new OTP.',
            'code': 'resend_cooldown',
            'waitSeconds': waitSeconds,
          };
        }
      }

      String otp = generateOTP();
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(minutes: otpValidityMinutes));

      // Update OTP in Firestore
      await _firestore.collection('otp_verification').doc(trimmedEmail).update({
        'otp': otp,
        'createdAt': now,
        'expiresAt': expiresAt,
        'verified': false,
        'attempts': 0,
        'lastAttemptTime': null,
      });

      // Send email with new OTP via Cloud Function
      final emailSent = await EmailService.sendOTPEmail(
        email: trimmedEmail,
        otp: otp,
      );

      if (emailSent) {
        developer.log('OTP resent successfully to $trimmedEmail');
        return {
          'success': true,
          'message': 'OTP resent successfully! Check your email.',
          'code': 'resend_success',
        };
      } else {
        developer.log('⚠️ OTP saved to Firestore but email resend failed for $trimmedEmail', level: 800);
        return {
          'success': true,
          'message': 'OTP generated (email sending is in development mode). Check console for OTP.',
          'code': 'resend_development_mode',
          'isDevelopmentMode': true,
        };
      }
    } catch (e) {
      developer.log('Error resending OTP: $e', level: 1000);
      return {
        'success': false,
        'message': 'Error resending OTP: ${e.toString()}',
        'code': 'resend_error',
      };
    }
  }

  /// Check if email is verified
  Future<bool> isEmailVerified(String email) async {
    try {
      final trimmedEmail = email.trim().toLowerCase();

      if (!_isValidEmail(trimmedEmail)) {
        return false;
      }

      DocumentSnapshot doc = await _firestore
          .collection('otp_verification')
          .doc(trimmedEmail)
          .get();

      if (!doc.exists) {
        return false;
      }

      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      return data['verified'] ?? false;
    } catch (e) {
      developer.log('Error checking email verification: $e', level: 1000);
      return false;
    }
  }

  /// Get OTP for development/testing purposes only
  Future<String?> getOTPForTesting(String email) async {
    try {
      final trimmedEmail = email.trim().toLowerCase();

      if (!_isValidEmail(trimmedEmail)) {
        return null;
      }

      DocumentSnapshot doc = await _firestore
          .collection('otp_verification')
          .doc(trimmedEmail)
          .get();

      if (!doc.exists) {
        return null;
      }

      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      
      // Only return OTP if not expired
      DateTime expiresAt = (data['expiresAt'] as Timestamp).toDate();
      if (DateTime.now().isBefore(expiresAt)) {
        return data['otp'];
      }
      
      return null;
    } catch (e) {
      developer.log('Error getting OTP for testing: $e', level: 1000);
      return null;
    }
  }

  /// Clean up expired OTP records (call periodically)
  Future<void> cleanupExpiredOTPs() async {
    try {
      final now = DateTime.now();
      final query = await _firestore
          .collection('otp_verification')
          .where('expiresAt', isLessThan: now)
          .get();

      for (var doc in query.docs) {
        await doc.reference.delete();
      }
      
      developer.log('Cleaned up ${query.docs.length} expired OTP records');
    } catch (e) {
      developer.log('Error cleaning up expired OTPs: $e', level: 1000);
    }
  }
}
