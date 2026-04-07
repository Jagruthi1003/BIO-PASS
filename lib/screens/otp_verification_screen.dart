import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String email;
  final VoidCallback onVerificationComplete;

  const OTPVerificationScreen({
    super.key,
    required this.email,
    required this.onVerificationComplete,
  });

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  int _remainingAttempts = 5;
  bool _canResend = true;
  int _resendCountdown = 60;
  bool _emailNotFound = false;

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
  }

  void _startResendCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _resendCountdown > 0) {
        setState(() {
          _resendCountdown--;
        });
        _startResendCountdown();
      } else if (mounted) {
        setState(() {
          _canResend = true;
        });
      }
    });
  }

  Future<void> _verifyOTP() async {
    if (_otpController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter the OTP';
      });
      return;
    }

    if (_otpController.text.length != 6 || !RegExp(r'^\d+$').hasMatch(_otpController.text)) {
      setState(() {
        _errorMessage = 'OTP must be 6 digits';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _authService.verifyEmailOTP(
        email: widget.email,
        otp: _otpController.text,
      );

      if (mounted) {
        if (result['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Email verified successfully!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          widget.onVerificationComplete();
        } else {
          // Check for specific error codes
          if (result['code'] == 'otp_not_found' || result['code'] == 'email_not_found') {
            setState(() {
              _emailNotFound = true;
              _errorMessage = 'Email not found. Please check your email address and sign up again.';
            });
          } else if (result['code'] == 'otp_expired') {
            setState(() {
              _errorMessage = 'OTP has expired. Please request a new OTP.';
              _remainingAttempts = 5;
            });
          } else if (result['code'] == 'max_attempts_exceeded') {
            setState(() {
              _errorMessage = 'Too many failed attempts. Please request a new OTP.';
              _remainingAttempts = 0;
            });
          } else {
            setState(() {
              _errorMessage = result['message'] ?? 'Verification failed';
              _remainingAttempts = result['remainingAttempts'] ?? _remainingAttempts;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resendOTP() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _emailNotFound = false;
    });

    try {
      final result = await _authService.resendOTP(email: widget.email);

      if (mounted) {
        if (result['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'OTP resent successfully!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );

          setState(() {
            _canResend = false;
            _resendCountdown = 60;
            _otpController.clear();
            _remainingAttempts = 5;
          });

          _startResendCountdown();
        } else {
          // Check for specific error codes
          if (result['code'] == 'otp_not_found' || result['code'] == 'no_previous_otp') {
            setState(() {
              _emailNotFound = true;
              _errorMessage = 'Email not found. Please sign up first.';
            });
          } else if (result['code'] == 'resend_cooldown') {
            setState(() {
              _errorMessage = result['message'] ?? 'Please wait before requesting another OTP';
            });
          } else {
            setState(() {
              _errorMessage = result['message'] ?? 'Failed to resend OTP. Please try again.';
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error resending OTP: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _goBackToSignUp() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Email Verification'),
          backgroundColor: Colors.deepPurple,
          elevation: 0,
          leading: _isLoading ? null : IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBackToSignUp,
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Email icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.mail,
                    size: 48,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  'Verify Your Email',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Email display
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    border: Border.all(color: Colors.blue.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'An OTP has been sent to:',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.email,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // OTP Input Field
                if (!_emailNotFound) ...[
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    enabled: !_isLoading,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      hintText: '000000',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 28,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.deepPurple.shade200,
                          width: 2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.deepPurple,
                          width: 2,
                        ),
                      ),
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    onChanged: (value) {
                      if (value.length == 6 && RegExp(r'^\d+$').hasMatch(value)) {
                        _verifyOTP();
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Error message
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Remaining attempts (only show if not email not found)
                if (!_emailNotFound && _remainingAttempts > 0)
                  Text(
                    'Remaining attempts: $_remainingAttempts',
                    style: TextStyle(
                      color: _remainingAttempts <= 2 ? Colors.red : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 24),

                // Action buttons
                if (!_emailNotFound) ...[
                  // Verify Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_isLoading || _remainingAttempts == 0) ? null : _verifyOTP,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Verify OTP',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Resend Button
                  TextButton(
                    onPressed: _canResend && !_isLoading ? _resendOTP : null,
                    child: Text(
                      _canResend
                          ? 'Resend OTP'
                          : 'Resend OTP in $_resendCountdown seconds',
                      style: TextStyle(
                        color: _canResend ? Colors.deepPurple : Colors.grey,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else ...[
                  // Email not found message
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _goBackToSignUp,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Go Back to Sign Up'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _isLoading ? null : _resendOTP,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Another Email'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

