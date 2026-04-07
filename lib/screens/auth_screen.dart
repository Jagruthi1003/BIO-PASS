import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../utils/validation_utils.dart';
import 'otp_verification_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _isLogin = true;
  String _selectedRole = 'attendee';
  bool _isLoading = false;
  String? _emailError;
  String? _passwordError;
  String? _nameError;
  bool _showPasswordRequirements = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(() {
      setState(() {
        if (_emailController.text.isNotEmpty && !_isLogin) {
          _emailError = ValidationUtils.validateEmail(_emailController.text);
        } else {
          _emailError = null;
        }
      });
    });

    _passwordController.addListener(() {
      setState(() {
        if (_passwordController.text.isNotEmpty && !_isLogin) {
          _passwordError = ValidationUtils.validatePassword(_passwordController.text);
          _showPasswordRequirements = true;
        } else {
          _showPasswordRequirements = false;
          _passwordError = null;
        }
      });
    });

    _nameController.addListener(() {
      setState(() {
        if (_nameController.text.isNotEmpty && !_isLogin) {
          _nameError = _nameController.text.trim().isEmpty ? 'Name is required' : null;
        } else {
          _nameError = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _authenticate() async {
    // Validate all fields
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    if (!_isLogin) {
      // Signup validation
      final emailError = ValidationUtils.validateEmail(_emailController.text);
      if (emailError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(emailError)),
        );
        return;
      }

      final passwordError = ValidationUtils.validatePassword(_passwordController.text);
      if (passwordError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(passwordError)),
        );
        return;
      }

      if (_nameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your full name')),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        final result = await _authService.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        if (mounted) {
          if (!result['success']) {
            if (result['requiresOTPVerification'] ?? false) {
              // Navigate to OTP verification screen
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => OTPVerificationScreen(
                    email: result['email'] ?? _emailController.text.trim(),
                    onVerificationComplete: () {
                      Navigator.of(context).pushReplacementNamed('/splash');
                    },
                  ),
                ),
              );
            } else {
              // Show error message with specific details
              String errorMessage = result['message'] ?? 'Login failed';
              if (result['code'] == 'user_not_found') {
                errorMessage = 'Email not found. Please sign up first.';
              } else if (result['code'] == 'wrong_password') {
                errorMessage = 'Incorrect password. Please try again.';
              }
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(errorMessage),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } else {
            Navigator.of(context).pushReplacementNamed('/splash');
          }
        }
      } else {
        final result = await _authService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim(),
          role: _selectedRole,
        );

        if (mounted) {
          if (result['success']) {
            // Navigate to OTP verification screen
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => OTPVerificationScreen(
                  email: _emailController.text.trim(),
                  onVerificationComplete: () {
                    Navigator.of(context).pushReplacementNamed('/splash');
                  },
                ),
              ),
            );
          } else {
            // Show error message with specific details
            String errorMessage = result['message'] ?? 'Signup failed';
            if (result['code'] == 'email_already_exists') {
              errorMessage = 'This email is already registered. Please log in instead.';
            } else if (result['code'] == 'invalid_email_format') {
              errorMessage = 'Invalid email format. Please check your email address.';
            } else if (result['code'] == 'weak_password') {
              errorMessage = 'Password is not strong enough. Please check requirements below.';
            }
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleAuthMode() {
    setState(() {
      _isLogin = !_isLogin;
      _emailError = null;
      _passwordError = null;
      _nameError = null;
      _showPasswordRequirements = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BiO Pass'),
        backgroundColor: Colors.deepPurple,
        elevation: 4,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            Icon(
              Icons.verified_user,
              size: 60,
              color: Colors.deepPurple.shade700,
            ),
            const SizedBox(height: 16),
            Text(
              _isLogin ? 'LOGIN' : 'SIGN UP',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isLogin ? 'Welcome back!' : 'Create your account',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 32),
            _buildTextField(
              controller: _emailController,
              label: 'Email Address',
              hint: _isLogin ? 'Enter your email' : 'Enter your @pondiuni.ac.in email',
              icon: Icons.email,
              keyboardType: TextInputType.emailAddress,
              errorText: _emailError,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _passwordController,
              label: 'Password',
              hint: 'Enter your password',
              icon: Icons.lock,
              obscureText: true,
              errorText: _passwordError,
            ),
            if (!_isLogin && _showPasswordRequirements) ...[
              const SizedBox(height: 12),
              _buildPasswordRequirementsDisplay(),
            ],
            const SizedBox(height: 16),
            if (!_isLogin) ...[
              _buildTextField(
                controller: _nameController,
                label: 'Full Name',
                hint: 'Enter your full name',
                icon: Icons.person,
                errorText: _nameError,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  labelText: 'Select Your Role',
                  labelStyle: const TextStyle(
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.bold,
                  ),
                  prefixIcon: const Icon(
                    Icons.person_outline,
                    color: Colors.deepPurple,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Colors.deepPurple,
                      width: 2,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Colors.deepPurple,
                      width: 2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Colors.deepPurple,
                      width: 2,
                    ),
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'attendee',
                    child: Text('Attendee'),
                  ),
                  DropdownMenuItem(
                    value: 'organizer',
                    child: Text('Organizer'),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _selectedRole = value ?? 'attendee');
                },
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _authenticate,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(
                        _isLogin ? Icons.login : Icons.app_registration,
                        color: Colors.white,
                        size: 20,
                      ),
                label: Text(
                  _isLoading
                      ? 'PROCESSING...'
                      : (_isLogin ? 'LOGIN' : 'SIGN UP'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple.shade700,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _toggleAuthMode,
              child: Text(
                _isLogin
                    ? 'Don\'t have an account? SIGN UP'
                    : 'Already have an account? LOGIN',
                style: const TextStyle(
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordRequirementsDisplay() {
    final requirements = ValidationUtils.getPasswordRequirements(_passwordController.text);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border.all(
          color: Colors.blue[200]!,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Password Requirements:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 8),
          ...requirements.map((req) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    req.isMet ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: req.isMet ? Colors.green : Colors.grey,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      req.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: req.isMet ? Colors.green[700] : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(
        color: Colors.black,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Colors.deepPurple,
          fontWeight: FontWeight.bold,
        ),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(
          icon,
          color: Colors.deepPurple,
        ),
        errorText: errorText,
        errorStyle: const TextStyle(
          color: Colors.red,
          fontSize: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: errorText != null ? Colors.red : Colors.deepPurple,
            width: 2,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: errorText != null ? Colors.red : Colors.deepPurple,
            width: 2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: errorText != null ? Colors.red : Colors.deepPurple,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }
}
