/// Validation utilities for email and password constraints
class ValidationUtils {
  // Email validation constants
  static const String validEmailDomain = '@pondiuni.ac.in';
  
  // Password constraints
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 128;

  /// Validate email format and domain
  /// Returns null if valid, or error message if invalid
  static String? validateEmail(String email) {
    email = email.trim();
    
    if (email.isEmpty) {
      return 'Email is required';
    }

    // Check basic email format
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(email)) {
      return 'Please enter a valid email address';
    }

    // Check for valid domain
    if (!email.toLowerCase().endsWith(validEmailDomain)) {
      return 'Email must be from $validEmailDomain domain';
    }

    return null; // Valid email
  }

  /// Validate password strength and constraints
  /// Returns null if valid, or error message if invalid
  static String? validatePassword(String password) {
    if (password.isEmpty) {
      return 'Password is required';
    }

    if (password.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters long';
    }

    if (password.length > maxPasswordLength) {
      return 'Password must not exceed $maxPasswordLength characters';
    }

    // Check for at least one uppercase letter
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter (A-Z)';
    }

    // Check for at least one lowercase letter
    if (!password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter (a-z)';
    }

    // Check for at least one digit
    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number (0-9)';
    }

    // Check for at least one special character
    if (!password.contains(RegExp(r'[@#$%^&*()_+\-=\[\]{};:,.<>?/\\|`~]'))) {
      return 'Password must contain at least one special character';
    }

    return null; // Valid password
  }

  /// Get password requirement list for UI display
  static List<PasswordRequirement> getPasswordRequirements(String password) {
    return [
      PasswordRequirement(
        label: 'At least 8 characters',
        isMet: password.length >= minPasswordLength,
      ),
      PasswordRequirement(
        label: 'Contains uppercase letter (A-Z)',
        isMet: password.contains(RegExp(r'[A-Z]')),
      ),
      PasswordRequirement(
        label: 'Contains lowercase letter (a-z)',
        isMet: password.contains(RegExp(r'[a-z]')),
      ),
      PasswordRequirement(
        label: 'Contains number (0-9)',
        isMet: password.contains(RegExp(r'[0-9]')),
      ),
      PasswordRequirement(
        label: 'Contains special character',
        isMet: password.contains(RegExp(r'[@#$%^&*()_+\-=\[\]{};:,.<>?/\\|`~]')),
      ),
    ];
  }

  /// Check if all password requirements are met
  static bool isPasswordStrong(String password) {
    return validatePassword(password) == null;
  }

  /// Check if email is valid
  static bool isEmailValid(String email) {
    return validateEmail(email) == null;
  }
}

/// Class to represent a single password requirement
class PasswordRequirement {
  final String label;
  final bool isMet;

  PasswordRequirement({
    required this.label,
    required this.isMet,
  });
}
