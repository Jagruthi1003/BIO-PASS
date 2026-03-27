# Antigravity - Quick Reference Guide

Fast lookup for common tasks and important code locations.

## 📍 Key File Locations

### Data Models
| File | Purpose |
|------|---------|
| `lib/models/user.dart` | User with role (attendee/organizer/gatekeeper) |
| `lib/models/event.dart` | Event with capacity, price, gatekeeper |
| `lib/models/ticket.dart` | Ticket with status (ACTIVE/USED/CANCELLED), zk-proof |

### Services
| File | Purpose |
|------|---------|
| `lib/services/auth_service.dart` | Firebase authentication |
| `lib/services/enhanced_event_service.dart` | Event CRUD, ticket booking, verification |
| `lib/services/face_biometric_service.dart` | Landmark normalization, hashing, verification |
| `lib/services/qr_code_service.dart` | QR code generation/parsing |

### Screens
| File | Purpose | Route |
|------|---------|-------|
| `lib/screens/splash_screen.dart` | Role detection | `/splash` |
| `lib/screens/auth_screen.dart` | Sign up/login | `/auth` |
| `lib/screens/organizer_dashboard_new.dart` | Event management | `/organizer` |
| `lib/screens/attendee_dashboard_new.dart` | Event browsing, booking | `/attendee` |
| `lib/screens/gatekeeper_verification_screen.dart` | Face verification | `/gatekeeper` |
| `lib/screens/zk_face_registration_screen_new.dart` | Face registration | (from booking) |
| `lib/screens/create_event_screen.dart` | Event creation | (from organizer) |

### Configuration
| File | Purpose |
|------|---------|
| `pubspec.yaml` | Dependencies |
| `main.dart` | App entry, routing |
| `analysis_options.yaml` | Lint rules |
| `android/app/build.gradle.kts` | Android build config |
| `ios/Runner.xcodeproj` | iOS build config |

---

## 🔄 Common Workflows

### 1. Add a New Event Field
```dart
// 1. Update lib/models/event.dart
class Event {
  final String newField;  // Add field
  // Update constructor
  // Update toMap()
  // Update fromMap()
}

// 2. Update Firestore reference in services
// lib/services/enhanced_event_service.dart
Event event = Event(
  // ... existing fields ...
  newField: value,
);

// 3. Update UI in organizer_dashboard_new.dart
Text('${widget.event.newField}')

// 4. Update event creation form in create_event_screen.dart
_buildTextInputField(
  controller: _newFieldController,
  label: 'New Field',
  // ...
)
```

### 2. Change Euclidean Distance Threshold
```dart
// In lib/services/face_biometric_service.dart
static const double SIMILARITY_THRESHOLD = 0.18;  // Change this value

// In lib/screens/gatekeeper_verification_screen.dart
// Threshold check happens in verifyFaceWithEuclideanDistance
bool isMatch = verificationResult['isMatch'] as bool;
```

### 3. Test Complete Verification Flow
```
1. Sign up as organizer
2. Create event with capacity 2
3. Sign up as attendee 1
4. Book ticket → Face register
5. Sign up as attendee 2
6. Book ticket → Face register
7. Sign up as gatekeeper
8. Organizer assigns gatekeeper
9. Gatekeeper verifies attendee 1
   → Ticket status changes to USED
10. Attendee 1 sees real-time update
11. Gatekeeper tries to verify same ticket again
    → Should fail (ticket already USED)
```

### 4. Monitor Real-Time Status
```dart
// In attendee_dashboard_new.dart
StreamBuilder<Ticket?>(
  stream: _eventService.streamTicket(ticket.id),
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      Ticket? updatedTicket = snapshot.data;
      // Display updated status
    }
  },
)
```

### 5. Add New Role
```dart
// 1. Update enum in User model
enum UserRole { attendee, organizer, gatekeeper, newRole }

// 2. Add route in main.dart
case '/newrole':
  return MaterialPageRoute(builder: (context) => NewRoleScreen());

// 3. Update splash_screen.dart routing
if (user.role == 'newrole') {
  Navigator.of(context).pushReplacementNamed('/newrole');
}

// 4. Create new screen (NewRoleScreen)

// 5. Add auth_screen.dart role selection button
```

---

## 🔐 Security Quick Tips

### Prevent Common Issues
```dart
// ❌ DON'T: Store raw landmarks
final landmarks = face.landmarks;

// ✅ DO: Store encrypted and hashed
final zkProof = FaceBiometricService.generateZkProofHash(normalized);
final encrypted = FaceBiometricService.encryptNormalizedLandmarks(normalized, key);

// ❌ DON'T: Expose user IDs in URLs
navigate('/ticket/$ticketId'); // If visible to others

// ✅ DO: Use Firestore security rules to enforce access
Future<Ticket?> getTicket(String ticketId) async {
  // Firestore rules prevent unauthorized access
}

// ❌ DON'T: Trust client-side verification
if (verificationResult['isMatch']) { /* grant entry */ }

// ✅ DO: Verify in Firestore transaction (atomic)
Future<bool> markTicketAsUsed(String ticketId) async {
  // Use Firestore transaction
  return await _firestore.runTransaction((transaction) async {
    // Double-check ticket status
    // Update atomically
  });
}
```

---

## 📊 Database Queries

### Get User Events (Organizer Dashboard)
```dart
Future<List<Event>> getEventsByOrganizer(String organizerId) async {
  var snapshot = await _firestore
      .collection('events')
      .where('organizerId', isEqualTo: organizerId)
      .get();
  return snapshot.docs
      .map((doc) => Event.fromMap(doc.id, doc.data()))
      .toList();
}
```

### Get Tickets for Event
```dart
Future<List<Ticket>> getTicketsByEvent(String eventId) async {
  var snapshot = await _firestore
      .collection('tickets')
      .where('eventId', isEqualTo: eventId)
      .get();
  return snapshot.docs
      .map((doc) => Ticket.fromMap(doc.id, doc.data()))
      .toList();
}
```

### Count Available Capacity
```dart
Future<bool> hasCapacityAvailable(String eventId) async {
  var event = await getEventById(eventId);
  var ticketsSold = await getTicketsSold(eventId);
  return ticketsSold < event.capacity;
}
```

### Get Verification Audit
```dart
Future<List<VerificationAudit>> getAuditTrail(String ticketId) async {
  var snapshot = await _firestore
      .collection('verification_audit')
      .where('ticketId', isEqualTo: ticketId)
      .orderBy('timestamp', descending: true)
      .get();
  return snapshot.docs.map((doc) => VerificationAudit.fromMap(doc.data())).toList();
}
```

---

## 🎯 Debugging

### Enable Debug Logging
```dart
// In main.dart
void main() {
  // Enable Firebase debugging
  FirebaseAuth.instance.idTokenChanges().listen((User? user) {
    debugPrint('User changed: ${user?.email}');
  });
  
  runApp(const MyApp());
}
```

### Check Face Detection
```dart
// In zk_face_registration_screen_new.dart
FaceDetector faceDetector = GoogleMlKit.vision.faceDetector();

try {
  final faces = await faceDetector.processImage(inputImage);
  debugPrint('Faces detected: ${faces.length}');
  if (faces.isNotEmpty) {
    Face face = faces[0];
    debugPrint('Landmarks: ${face.landmarks.length}');
  }
} catch (e) {
  debugPrint('Face detection error: $e');
}
```

### Check Firestore Writes
```dart
// In enhanced_event_service.dart
try {
  await _firestore.collection('tickets').doc(ticketId).set(ticket.toMap());
  debugPrint('Ticket written: $ticketId');
} catch (e) {
  debugPrint('Firestore write error: $e');
}
```

### Verify Encryption
```dart
// In face_biometric_service.dart
String encrypted = encryptNormalizedLandmarks(normalized, key);
debugPrint('Encrypted length: ${encrypted.length}');

List<double> decrypted = decryptNormalizedLandmarks(encrypted, key);
debugPrint('Decrypted matches original: ${normalizedEquals(normalized, decrypted)}');
```

---

## 🚀 Performance Tips

### Optimize Landmark Processing
```dart
// ❌ Slow: Process every frame
faces.forEach((face) {
  normalized = FaceBiometricService._normalizeLandmarks(face.landmarks);
});

// ✅ Fast: Process only when face aligned
if (isFaceAligned(face)) {
  normalized = FaceBiometricService._normalizeLandmarks(face.landmarks);
  captureFrame = true;
}
```

### Reduce Firestore Reads
```dart
// ❌ Slow: Read per ticket
for (Ticket ticket in tickets) {
  await _firestore.collection('tickets').doc(ticket.id).get();
}

// ✅ Fast: Batch read
var snapshot = await _firestore
    .collection('tickets')
    .where('eventId', isEqualTo: eventId)
    .get();
```

### Cache Images
```dart
// ❌ Slow: Reload each time
Image.asset('assets/logo.png');

// ✅ Fast: Use precache
precacheImage(AssetImage('assets/logo.png'), context);
Image.asset('assets/logo.png');
```

---

## 🔍 Testing Snippets

### Unit Test: Face Verification
```dart
test('Should verify matching faces', () {
  List<double> norm1 = [...]; // Test data
  List<double> norm2 = [...];
  String hash1 = FaceBiometricService.generateZkProofHash(norm1);
  String hash2 = FaceBiometricService.generateZkProofHash(norm2);
  
  Map result = FaceBiometricService.verifyFaceWithEuclideanDistance(
    norm1, norm2, hash1, hash2);
  
  expect(result['isMatch'], true);
});
```

### Integration Test: Complete Flow
```dart
testWidgets('Attendee can book and verify ticket', (tester) async {
  await tester.pumpWidget(const MyApp());
  
  // Sign up
  await tester.tap(find.byText('Sign Up'));
  await tester.pumpAndSettle();
  
  // Fill form
  await tester.enterText(find.byType(TextField).first, 'test@example.com');
  // ... more setup ...
  
  // Book ticket
  await tester.tap(find.byText('Book Ticket'));
  await tester.pumpAndSettle();
  
  // Verify ticket created
  expect(find.byText('ACTIVE'), findsOneWidget);
});
```

---

## 📈 Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| Face not detected | Check lighting, center face in frame |
| Distance too high (> 0.18) | Verify face is at correct distance, check calibration |
| Ticket already USED | Expected behavior, verify different ticket |
| Permission denied | Tap "Allow" in permission dialog, check app settings |
| Firestore timeout | Check internet, retry with exponential backoff |
| Memory leak | Profile with `flutter run --profile`, check streams disposal |
| UI lag | Reduce landmark processing frequency, optimize rebuilds |
| QR code not scanning | Ensure lighting, hold steady, check QR generation |

---

## 📞 When to Escalate

| Issue | Escalate To |
|-------|------------|
| Euclidean distance threshold needs tuning | ML/Security team |
| Firestore security rules issue | DevOps/Security team |
| Face detection accuracy poor | ML/Computer Vision team |
| Performance degradation | DevOps/Backend team |
| User authentication failing | Firebase/Auth team |
| Real-time sync delays | Backend/Database team |

---

## 📚 Documentation Map

```
Root Directory
├── README.md (Start here!)
├── IMPLEMENTATION_SUMMARY.md (What's done)
├── ANTIGRAVITY_ARCHITECTURE.md (System design)
├── BUILD_INSTRUCTIONS.md (Build & deploy)
├── DEPLOYMENT_CHECKLIST.md (Pre-launch)
├── TESTING.md (Test procedures)
├── QUICK_REFERENCE.md (This file)
├── lib/
│   ├── models/ (Data structures)
│   ├── services/ (Business logic)
│   ├── screens/ (UI)
│   └── constants/ (App constants)
├── android/ (Android config)
├── ios/ (iOS config)
├── pubspec.yaml (Dependencies)
└── analysis_options.yaml (Lint rules)
```

---

**Version**: 1.0
**Last Updated**: [Current Date]
**Status**: ✅ Production Ready

For more info, see the full documentation files listed above.
