import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Service for sending emails via Firebase Cloud Function
/// Handles OTP sending, verification emails, and validation
class EmailService {
  // ⚠️ IMPORTANT: Replace YOUR_PROJECT_ID with your actual Firebase Project ID
  // Find it in Firebase Console > Project Settings > Project ID
  // Format: https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/sendOTPEmail
  static const String cloudFunctionUrl = 
    'https://us-central1-zk-event-entry.cloudfunctions.net/sendOTPEmail';
  
  // Test endpoint to verify email configuration
  static const String testEmailUrl = 
    'https://us-central1-zk-event-entry.cloudfunctions.net/testEmail';
  
  // Production-ready mode: Set to false for PRODUCTION to actually send emails
  // Set to true only for development/testing (OTP shown in console only)
  static const bool isDevelopmentMode = false;
  
  // Email configuration constants
  static const String emailFrom = 'noreply@biopass.app';
  static const String appName = 'BiO Pass';
  static const int emailTimeout = 30; // seconds
  static const int maxRetries = 3;

  /// Validate if email is properly formatted
  static bool isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email.trim());
  }

  /// Send OTP via email using Cloud Function
  /// Returns true if email sent successfully OR in development mode
  static Future<bool> sendOTPEmail({
    required String email,
    required String otp,
  }) async {
    try {
      // Validate email format first
      if (!isValidEmail(email)) {
        developer.log('Invalid email format: $email', level: 1000);
        return false;
      }

      // In development mode, just log OTP to console
      if (isDevelopmentMode) {
        developer.log('═════════════════════════════════════════════');
        developer.log('DEVELOPMENT MODE - OTP for Testing');
        developer.log('═════════════════════════════════════════════');
        developer.log('Email: $email');
        developer.log('OTP Code: $otp');
        developer.log('Valid for: 10 minutes');
        developer.log('═════════════════════════════════════════════');
        return true;
      }

      // Production mode: Send email via Cloud Function
      developer.log('Sending OTP to $email via Cloud Function...');
      
      final response = await http.post(
        Uri.parse(cloudFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'otp': otp,
          'type': 'otp_verification',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(
        const Duration(seconds: emailTimeout),
        onTimeout: () {
          developer.log('Cloud Function request timeout after $emailTimeout seconds', level: 1000);
          return http.Response('timeout', 408);
        },
      );

      if (response.statusCode == 200) {
        developer.log('OTP email sent successfully to $email');
        developer.log('Response: ${response.body}');
        return true;
      } else if (response.statusCode == 404) {
        developer.log('Email not found or invalid: $email', level: 1000);
        return false;
      } else {
        developer.log('Failed to send OTP: HTTP ${response.statusCode}', level: 1000);
        developer.log('Response: ${response.body}', level: 1000);
        return false;
      }
    } catch (e) {
      developer.log('Exception while sending OTP: $e', level: 1000);
      return false;
    }
  }

  /// Send verification confirmation email
  static Future<bool> sendVerificationConfirmationEmail({
    required String email,
    required String userName,
  }) async {
    try {
      // Validate email format first
      if (!isValidEmail(email)) {
        developer.log('Invalid email format: $email', level: 1000);
        return false;
      }

      if (isDevelopmentMode) {
        developer.log('[DEV MODE] Verification confirmation email would be sent to: $email for user: $userName');
        return true;
      }

      developer.log('Sending confirmation email to $email...');
      
      final response = await http.post(
        Uri.parse(cloudFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'userName': userName,
          'type': 'verification_confirmation',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(
        const Duration(seconds: emailTimeout),
        onTimeout: () => http.Response('timeout', 408),
      );

      if (response.statusCode == 200) {
        developer.log('Confirmation email sent successfully to $email');
        return true;
      } else if (response.statusCode == 404) {
        developer.log('Email not found or invalid: $email', level: 1000);
        return false;
      } else {
        developer.log('Failed to send confirmation email: HTTP ${response.statusCode}', level: 1000);
        developer.log('Response: ${response.body}', level: 1000);
        return false;
      }
    } catch (e) {
      developer.log('Exception while sending confirmation email: $e', level: 1000);
      return false;
    }
  }

  /// Send password reset email
  static Future<bool> sendPasswordResetEmail({
    required String email,
    required String resetLink,
  }) async {
    try {
      // Validate email format first
      if (!isValidEmail(email)) {
        developer.log('Invalid email format: $email', level: 1000);
        return false;
      }

      if (isDevelopmentMode) {
        developer.log('[DEV MODE] Password reset email would be sent to: $email with link: $resetLink');
        return true;
      }

      developer.log('Sending password reset email to $email...');
      
      final response = await http.post(
        Uri.parse(cloudFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'resetLink': resetLink,
          'type': 'password_reset',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(
        const Duration(seconds: emailTimeout),
        onTimeout: () => http.Response('timeout', 408),
      );

      if (response.statusCode == 200) {
        developer.log('Password reset email sent successfully to $email');
        return true;
      } else if (response.statusCode == 404) {
        developer.log('Email not found: $email', level: 1000);
        return false;
      } else {
        developer.log('Failed to send password reset email: HTTP ${response.statusCode}', level: 1000);
        return false;
      }
    } catch (e) {
      developer.log('Exception while sending password reset email: $e', level: 1000);
      return false;
    }
  }

  /// Test email configuration (useful for debugging)
  static Future<bool> testEmailConfiguration(String testEmail) async {
    try {
      if (!isValidEmail(testEmail)) {
        developer.log('Invalid email format for testing: $testEmail', level: 1000);
        return false;
      }

      developer.log('Testing email configuration...');
      
      final response = await http.get(
        Uri.parse('$testEmailUrl?email=$testEmail'),
      ).timeout(
        const Duration(seconds: emailTimeout),
        onTimeout: () => http.Response('timeout', 408),
      );

      if (response.statusCode == 200) {
        developer.log('Email configuration test passed!');
        developer.log('Response: ${response.body}');
        return true;
      } else {
        developer.log('Email configuration test failed: HTTP ${response.statusCode}', level: 1000);
        developer.log('Response: ${response.body}', level: 1000);
        return false;
      }
    } catch (e) {
      developer.log('Exception during email configuration test: $e', level: 1000);
      return false;
    }
  }
}
