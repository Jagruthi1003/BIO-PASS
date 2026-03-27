import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _checkUserStatus();
  }

  void _checkUserStatus() async {
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      final user = await _authService.getCurrentUser();
      if (mounted) {
        if (user != null) {
          if (user.role == 'attendee') {
            Navigator.of(context).pushReplacementNamed(
              '/attendee',
              arguments: user.toMap(),
            );
          } else if (user.role == 'organizer') {
            Navigator.of(context).pushReplacementNamed(
              '/organizer',
              arguments: user.toMap(),
            );
          } else {
            Navigator.of(context).pushReplacementNamed('/auth');
          }
        } else {
          Navigator.of(context).pushReplacementNamed('/auth');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_user, size: 80, color: Colors.blue),
            SizedBox(height: 20),
            Text(
              'BiO Pass',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Biometric Pass System',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 40),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

