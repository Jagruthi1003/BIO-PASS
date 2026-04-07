import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';
import '../utils/validation_utils.dart';
import 'otp_service.dart';
import 'email_service.dart';

class AuthService {
  final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final OTPService _otpService = OTPService();

  /// Sign up a new user with email verification
  /// Returns a detailed map with success status and next steps
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    try {
      final trimmedEmail = email.trim().toLowerCase();
      final trimmedName = name.trim();

      // Validate email format and domain
      final emailError = ValidationUtils.validateEmail(trimmedEmail);
      if (emailError != null) {
        return {
          'success': false,
          'message': emailError,
          'code': 'invalid_email_format',
        };
      }

      // Validate password strength
      final passwordError = ValidationUtils.validatePassword(password);
      if (passwordError != null) {
        return {
          'success': false,
          'message': passwordError,
          'code': 'weak_password',
        };
      }

      // Validate name is not empty
      if (trimmedName.isEmpty) {
        return {
          'success': false,
          'message': 'Full name is required',
          'code': 'missing_name',
        };
      }

      // Create Firebase Auth user
      auth.UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );

      final userId = userCredential.user!.uid;

      // Create user model
      User user = User(
        uid: userId,
        email: trimmedEmail,
        name: trimmedName,
        role: role,
      );

      // Store user in Firestore but mark as not verified
      await _firestore.collection('users').doc(userId).set({
        ...user.toMap(),
        'emailVerified': false,
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
        'status': 'pending_verification',
      });

      // Send OTP for email verification
      final otpResult = await _otpService.sendOTP(
        email: trimmedEmail,
        userID: userId,
      );

      if (otpResult['success']) {
        return {
          'success': true,
          'message': 'Account created successfully! OTP sent to your email.',
          'user': user,
          'requiresOTPVerification': true,
          'email': trimmedEmail,
          'code': 'signup_success',
        };
      } else {
        // OTP sending failed but account was created
        return {
          'success': false,
          'message': 'Account created but OTP sending failed. ${otpResult['message']}',
          'user': user,
          'requiresOTPVerification': true,
          'email': trimmedEmail,
          'code': 'signup_partial_failure',
        };
      }
    } on auth.FirebaseAuthException catch (e) {
      String message = 'Registration failed';
      String code = 'auth_error';

      if (e.code == 'weak-password') {
        message = 'Password is too weak. Please use a stronger password.';
        code = 'weak_password';
      } else if (e.code == 'email-already-in-use') {
        message = 'This email is already registered. Please log in or use a different email.';
        code = 'email_already_exists';
      } else if (e.code == 'invalid-email') {
        message = 'The email address is invalid.';
        code = 'invalid_email_format';
      }

      return {
        'success': false,
        'message': message,
        'code': code,
        'firebaseErrorCode': e.code,
      };
    } catch (e) {
      developer.log('Signup error: $e', level: 1000);
      return {
        'success': false,
        'message': 'An unexpected error occurred during registration. Please try again.',
        'code': 'unexpected_error',
        'error': e.toString(),
      };
    }
  }

  /// Verify email using OTP
  /// Called after user enters the OTP code
  Future<Map<String, dynamic>> verifyEmailOTP({
    required String email,
    required String otp,
  }) async {
    try {
      final trimmedEmail = email.trim().toLowerCase();
      final trimmedOTP = otp.trim();

      // Validate email format
      final emailError = ValidationUtils.validateEmail(trimmedEmail);
      if (emailError != null) {
        return {
          'success': false,
          'message': 'Invalid email format',
          'code': 'invalid_email_format',
        };
      }

      // Call OTP service to verify
      final result = await _otpService.verifyOTP(
        email: trimmedEmail,
        enteredOTP: trimmedOTP,
      );

      if (result['success']) {
        final userID = result['userID'];

        // Update user document to mark email as verified
        await _firestore.collection('users').doc(userID).update({
          'emailVerified': true,
          'emailVerifiedAt': DateTime.now(),
          'status': 'active',
          'updatedAt': DateTime.now(),
        });

        // Send confirmation email
        final userDoc = await _firestore.collection('users').doc(userID).get();
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          await EmailService.sendVerificationConfirmationEmail(
            email: trimmedEmail,
            userName: userData['name'] ?? 'User',
          );
        }

        return {
          'success': true,
          'message': 'Email verified successfully! You can now log in.',
          'code': 'verification_success',
        };
      } else {
        return {
          'success': false,
          'message': result['message'] ?? 'Email verification failed',
          'code': result['code'] ?? 'verification_failed',
          'remainingAttempts': result['remainingAttempts'],
        };
      }
    } catch (e) {
      developer.log('Email verification error: $e', level: 1000);
      return {
        'success': false,
        'message': 'Error verifying email: ${e.toString()}',
        'code': 'verification_error',
      };
    }
  }

  /// Resend OTP to user's email
  /// Includes cooldown to prevent abuse
  Future<Map<String, dynamic>> resendOTP({required String email}) async {
    try {
      final trimmedEmail = email.trim().toLowerCase();

      // Validate email format
      final emailError = ValidationUtils.validateEmail(trimmedEmail);
      if (emailError != null) {
        return {
          'success': false,
          'message': 'Invalid email format',
          'code': 'invalid_email_format',
        };
      }

      // Call OTP service to resend
      final result = await _otpService.resendOTP(email: trimmedEmail);

      if (result['success']) {
        return {
          'success': true,
          'message': result['message'] ?? 'OTP has been resent to your email.',
          'code': 'resend_success',
        };
      } else {
        return {
          'success': false,
          'message': result['message'] ?? 'Failed to resend OTP. Please try again.',
          'code': result['code'] ?? 'resend_failed',
          'waitSeconds': result['waitSeconds'],
        };
      }
    } catch (e) {
      developer.log('Resend OTP error: $e', level: 1000);
      return {
        'success': false,
        'message': 'Error resending OTP: ${e.toString()}',
        'code': 'resend_error',
      };
    }
  }

  /// Login user with email verification check
  /// Ensures email is verified before granting access
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final trimmedEmail = email.trim().toLowerCase();

      // Validate inputs
      if (trimmedEmail.isEmpty || password.isEmpty) {
        return {
          'success': false,
          'message': 'Email and password are required',
          'code': 'missing_credentials',
        };
      }

      // Validate email format
      final emailError = ValidationUtils.validateEmail(trimmedEmail);
      if (emailError != null) {
        return {
          'success': false,
          'message': emailError,
          'code': 'invalid_email_format',
        };
      }

      // Sign in with Firebase Auth
      auth.UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );

      final userId = userCredential.user!.uid;

      // Get user document from Firestore
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(userId)
          .get();

      if (!doc.exists) {
        // User in Auth but not in Firestore - create entry
        User newUser = User(
          uid: userId,
          email: trimmedEmail,
          name: 'User',
          role: 'attendee',
        );

        await _firestore.collection('users').doc(userId).set({
          ...newUser.toMap(),
          'emailVerified': false,
          'createdAt': DateTime.now(),
          'updatedAt': DateTime.now(),
          'status': 'pending_verification',
        });

        return {
          'success': false,
          'message': 'Email not verified. OTP sent to your email.',
          'requiresOTPVerification': true,
          'email': trimmedEmail,
          'code': 'email_not_verified',
        };
      }

      Map<String, dynamic> userData = doc.data() as Map<String, dynamic>;

      // Check if email is verified
      bool emailVerified = userData['emailVerified'] ?? false;

      if (!emailVerified) {
        // Send OTP again for verification
        final otpResult = await _otpService.sendOTP(
          email: trimmedEmail,
          userID: userId,
        );

        return {
          'success': false,
          'message': 'Email not verified. OTP sent to your email.',
          'requiresOTPVerification': true,
          'email': trimmedEmail,
          'code': 'email_not_verified',
          'otpSent': otpResult['success'],
        };
      }

      // Email is verified, allow login
      User user = User.fromMap(userData);
      
      // Update last login
      await _firestore.collection('users').doc(userId).update({
        'lastLogin': DateTime.now(),
        'updatedAt': DateTime.now(),
      });

      return {
        'success': true,
        'message': 'Login successful!',
        'user': user,
        'requiresOTPVerification': false,
        'code': 'login_success',
      };
    } on auth.FirebaseAuthException catch (e) {
      String message = 'Login failed';
      String code = 'auth_error';

      if (e.code == 'user-not-found') {
        message = 'No account found with this email. Please sign up first.';
        code = 'user_not_found';
      } else if (e.code == 'wrong-password') {
        message = 'Incorrect password. Please try again.';
        code = 'wrong_password';
      } else if (e.code == 'user-disabled') {
        message = 'This account has been disabled. Please contact support.';
        code = 'user_disabled';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address.';
        code = 'invalid_email';
      }

      return {
        'success': false,
        'message': message,
        'code': code,
        'firebaseErrorCode': e.code,
      };
    } catch (e) {
      developer.log('Login error: $e', level: 1000);
      return {
        'success': false,
        'message': 'An unexpected error occurred. Please try again.',
        'code': 'unexpected_error',
        'error': e.toString(),
      };
    }
  }

  /// Logout current user
  Future<void> logout() async {
    try {
      await _auth.signOut();
      developer.log('User logged out successfully');
    } catch (e) {
      developer.log('Logout error: $e', level: 1000);
      rethrow;
    }
  }

  /// Get current authenticated user
  Future<User?> getCurrentUser() async {
    try {
      auth.User? firebaseUser = _auth.currentUser;
      if (firebaseUser != null) {
        DocumentSnapshot doc = await _firestore
            .collection('users')
            .doc(firebaseUser.uid)
            .get();

        if (doc.exists) {
          return User.fromMap(doc.data() as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      developer.log('Error getting current user: $e', level: 1000);
      return null;
    }
  }

  /// Check if user's email is verified
  Future<bool> isUserEmailVerified(String userId) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(userId)
          .get();

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        return data['emailVerified'] ?? false;
      }
      return false;
    } catch (e) {
      developer.log('Error checking email verification: $e', level: 1000);
      return false;
    }
  }
}
