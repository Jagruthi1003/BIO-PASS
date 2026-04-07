import 'package:bio_pass/models/user.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:developer' as developer;
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/attendee_dashboard_new.dart';
import 'screens/organizer_dashboard_new.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Suppress Firebase platform channel threading warnings on Windows
  FlutterError.onError = (FlutterErrorDetails errorDetails) {
    if (!errorDetails.toString().contains('Platform channel')) {
      FlutterError.presentError(errorDetails);
    } else {
      developer.log(
        'Firebase platform channel message (non-critical): ${errorDetails.toString()}',
        level: 500,
      );
    }
  };

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    developer.log('Firebase initialization error: $e', level: 1000);
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BiO Pass',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const SplashScreen(),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/splash':
            return MaterialPageRoute(
              builder: (context) => const SplashScreen(),
              settings: settings,
            );
          case '/auth':
            return MaterialPageRoute(
              builder: (context) => const AuthScreen(),
              settings: settings,
            );
          case '/attendee':
            final user = User.fromMap(settings.arguments as Map<String, dynamic>);
            return MaterialPageRoute(
              builder: (context) => AttendeeDashboardNew(user: user),
              settings: settings,
            );
          case '/organizer':
            final user = User.fromMap(settings.arguments as Map<String, dynamic>);
            return MaterialPageRoute(
              builder: (context) => OrganizerDashboardNew(user: user),
              settings: settings,
            );
          default:
            return MaterialPageRoute(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('Not Found')),
                body: Center(
                  child: Text('Route ${settings.name} not found'),
                ),
              ),
              settings: settings,
            );
        }
      },
    );
  }
}
