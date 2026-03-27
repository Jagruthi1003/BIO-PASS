# Antigravity Testing Guide

Complete testing procedures for the biometric-powered event ticketing platform.

## Test Environment Setup

### Prerequisites
- Flutter 3.22.0+
- Android SDK 21+ or iOS 11+
- Two devices/emulators (one for testing, one for multi-user scenarios)
- Test Firebase project configured
- Test Firestore database initialized

### Test Data
- Test organizer: organizer@test.com / password123
- Test attendee 1: attendee1@test.com / password123
- Test attendee 2: attendee2@test.com / password123
- Test gatekeeper: gatekeeper@test.com / password123
- Test event: "Test Conference 2024", capacity 5, price $25

---

## Unit Tests

### 1. Face Biometric Service Tests

#### Test: Landmark Normalization
```dart
test('Should normalize landmarks correctly', () {
  List<double> rawLandmarks = [...]; // 68-point landmarks
  List<double> normalized = FaceBiometricService._normalizeLandmarks(rawLandmarks);
  
  // Verify:
  // - All points centered around (0, 0) for nose
  // - Magnitude scaled to inter-ocular distance
  // - Consistent output for same input
  expect(normalized.length, 136); // 68 * 2 (x, y)
  expect(normalized[0], closeTo(0.0, 0.01)); // Nose x near 0
  expect(normalized[1], closeTo(0.0, 0.01)); // Nose y near 0
});
```

#### Test: SHA-256 Hash Generation
```dart
test('Should generate consistent SHA-256 hash', () {
  List<double> normalized = [1.234, 5.678, ...];
  String hash1 = FaceBiometricService.generateZkProofHash(normalized);
  String hash2 = FaceBiometricService.generateZkProofHash(normalized);
  
  expect(hash1, equals(hash2));
  expect(hash1.length, equals(64)); // SHA-256 hex length
});
```

#### Test: Euclidean Distance Calculation
```dart
test('Should calculate Euclidean distance correctly', () {
  List<double> point1 = [0.0, 0.0, 0.0, 0.0];
  List<double> point2 = [3.0, 4.0, 0.0, 0.0];
  
  double distance = FaceBiometricService.calculateEuclideanDistance(point1, point2);
  
  // sqrt(3² + 4²) = 5
  expect(distance, closeTo(5.0, 0.001));
});
```

#### Test: Face Verification
```dart
test('Should verify matching faces', () {
  List<double> normalized1 = [...]; // Same face, same conditions
  List<double> normalized2 = [...]; // Same face, same conditions
  String hash1 = FaceBiometricService.generateZkProofHash(normalized1);
  String hash2 = FaceBiometricService.generateZkProofHash(normalized2);
  
  Map<String, dynamic> result = 
    FaceBiometricService.verifyFaceWithEuclideanDistance(
      normalized1, normalized2, hash1, hash2);
  
  expect(result['isMatch'], true);
  expect(result['matchStatus'], 'perfect_match');
});
```

### 2. QR Code Service Tests

#### Test: QR Code Generation
```dart
test('Should generate valid QR code data', () {
  String qrData = QrCodeService.generateQrCodeData(
    ticketId: 'TEST_0001',
    eventId: 'evt_123',
    attendeeId: 'att_456',
  );
  
  expect(qrData, equals('TEST_0001|evt_123|att_456'));
});
```

#### Test: QR Code Parsing
```dart
test('Should parse QR code data correctly', () {
  String qrData = 'TEST_0001|evt_123|att_456';
  Map<String, String> parsed = QrCodeService.parseQrCodeData(qrData);
  
  expect(parsed['ticketId'], equals('TEST_0001'));
  expect(parsed['eventId'], equals('evt_123'));
  expect(parsed['attendeeId'], equals('att_456'));
});
```

### 3. Enhanced Event Service Tests

#### Test: Ticket Booking
```dart
test('Should book ticket with capacity validation', () async {
  // Create event with capacity 2
  String eventId = await eventService.createEvent(
    organizerId: 'org_1',
    name: 'Small Event',
    description: 'Test',
    eventDate: DateTime.now().add(Duration(days: 1)),
    location: 'Test Location',
    capacity: 2,
    ticketPrice: 25.0,
  );
  
  // Book first ticket
  String ticket1 = await eventService.bookTicket(
    eventId: eventId,
    attendeeId: 'att_1',
    attendeeName: 'John',
    attendeeEmail: 'john@test.com',
  );
  expect(ticket1, isNotNull);
  
  // Book second ticket
  String ticket2 = await eventService.bookTicket(
    eventId: eventId,
    attendeeId: 'att_2',
    attendeeName: 'Jane',
    attendeeEmail: 'jane@test.com',
  );
  expect(ticket2, isNotNull);
  
  // Third booking should fail (capacity exceeded)
  expect(
    () => eventService.bookTicket(
      eventId: eventId,
      attendeeId: 'att_3',
      attendeeName: 'Jack',
      attendeeEmail: 'jack@test.com',
    ),
    throwsException,
  );
});
```

#### Test: Atomic Transaction (Prevent Double-Entry)
```dart
test('Should prevent double-entry with atomic transaction', () async {
  // Two concurrent verification attempts on same ticket
  Future<bool> verify1 = eventService.markTicketAsUsed(
    ticketId: 'ticket_123',
    gatekeeperId: 'gk_1',
    euclideanDistance: 0.12,
  );
  
  Future<bool> verify2 = eventService.markTicketAsUsed(
    ticketId: 'ticket_123',
    gatekeeperId: 'gk_2',
    euclideanDistance: 0.15,
  );
  
  List<bool> results = await Future.wait([verify1, verify2]);
  
  // Only one should succeed
  expect(results.where((r) => r).length, equals(1));
});
```

---

## Integration Tests

### 1. End-to-End Attendee Flow

#### Setup
1. Clear test Firestore database
2. Create test organizer account
3. Create test event with 10 capacity
4. Clear test attendee accounts

#### Test Steps
```
STEP 1: Attendee Sign Up
- Email: attendee1@test.com
- Password: password123
- Role: Attendee
- Expected: Account created, role saved to Firestore

STEP 2: Browse Events
- Navigate to Attendee Dashboard
- Go to "Browse Events" tab
- Expected: Test event appears in list
- Verify: Event shows name, date, capacity (0/10), price ($25)

STEP 3: Book Ticket
- Click "Book Ticket" on test event
- Expected: Capacity validation passes (0 < 10)
- Navigate to Face Registration screen
- Verify: Device prompts for camera permission

STEP 4: Face Registration
- Align face in guide frame
- Auto-capture when face detected
- Expected: Face guide overlay appears
- Verify: Landmarks extracted successfully
- Verify: ZK proof hash generated
- Verify: Encrypted vector stored

STEP 5: Ticket Created
- Navigate to "My Tickets" tab
- Expected: Ticket appears with ACTIVE status
- Verify: QR code displays
- Verify: Event details shown

STEP 6: Real-Time Update
- (Gatekeeper scans and verifies in another session)
- Expected: Ticket status updates to USED automatically
- Verify: Entry timestamp displays
- Verify: Gatekeeper name displays
- Verify: Euclidean distance metric shows

STEP 7: Capacity Verification
- Gatekeeper verification complete
- Organizer checks "My Events" capacity dashboard
- Expected: Capacity shows 1/10 used
```

### 2. End-to-End Organizer Flow

#### Setup
1. Clear test Firestore database
2. Clear test organizer account

#### Test Steps
```
STEP 1: Organizer Sign Up
- Email: organizer@test.com
- Password: password123
- Role: Organizer
- Expected: Account created, role saved to Firestore

STEP 2: Create Event
- Navigate to Organizer Dashboard
- Click Floating Action Button
- Fill form:
  - Name: "Test Conference"
  - Description: "A test event for verification"
  - Date: Tomorrow at 10:00 AM
  - Location: "Test Convention Center"
  - Capacity: 50
  - Ticket Price: $49.99
- Expected: Event created successfully
- Verify: Event appears in "My Events" tab

STEP 3: View Dashboard
- "My Events" tab shows created event
- Capacity bar shows 0/50 (green)
- Expected: All fields displayed correctly

STEP 4: Assign Gatekeeper
- Click event card → "Assign Gatekeeper"
- Enter: gatekeeper@test.com
- Expected: Gatekeeper assigned successfully
- Verify: "Gatekeepers" tab shows gatekeeper name

STEP 5: Monitor Attendance
- (Attendees book tickets in parallel)
- Refresh "My Events"
- Expected: Capacity bar updates in real-time
- As tickets → USED, bar fills proportionally

STEP 6: Remove Gatekeeper
- "Gatekeepers" tab → Select gatekeeper
- Click "Remove"
- Confirm removal
- Expected: Gatekeeper removed successfully
- Verify: No longer appears in gatekeepers list
```

### 3. End-to-End Gatekeeper Flow

#### Setup
1. Organizer creates event
2. Organizer assigns gatekeeper@test.com as gatekeeper
3. Attendees book tickets and register faces

#### Test Steps
```
STEP 1: Gatekeeper Login
- Email: gatekeeper@test.com
- Password: password123
- Role: Assigned by Organizer
- Expected: Navigates to /gatekeeper route

STEP 2: QR Code Scanning (or Manual Entry)
- "Scan QR" tab open
- Option A: Scan QR code from attendee's ticket
- Option B: Manually enter ticket ID
- Expected: Ticket loaded from Firestore
- Verify: Attendee name, event name, date displayed

STEP 3: Face Verification Setup
- Click "Verify Face"
- Expected: Rear camera activates
- Verify: Face guide overlay appears

STEP 4: Live Face Capture
- Align face in guide frame
- Auto-capture when face detected
- Expected: Landmarks extracted
- Verify: Face guide shows alignment feedback

STEP 5: Euclidean Distance Calculation
- Live landmarks normalized
- Distance calculated against stored landmarks
- Expected: Distance metric displays (e.g., "Distance: 0.14")
- Verify: Distance < 0.18 threshold for match

STEP 6: Verification Result
- Face match: Distance < 0.18
  - Expected: "✅ Entry Granted!" screen
  - Verify: Attendee name shown
  - Verify: Distance metric shown
  - Ticket status changed to USED in Firestore
- Face mismatch: Distance >= 0.18
  - Expected: "❌ Face Mismatch" screen
  - Verify: Distance shown
  - Verify: Entry denied message
  - Ticket remains ACTIVE

STEP 7: Audit Log Verification
- Check Firestore verification_audit collection
- Expected: Entry created with:
  - ticketId
  - gatekeeperId
  - timestamp
  - euclideanDistance
  - verificationStatus (verified or failed)

STEP 8: Real-Time Sync
- Attendee checks "My Tickets" in other app instance
- Expected: Ticket status updates automatically
- Verify: USED status, timestamp, gatekeeper name
```

---

## UI/UX Tests

### 1. Navigation & Routing

#### Attendee Routing
- [ ] Splash screen routes to /attendee after login
- [ ] All attendee-specific screens accessible
- [ ] Cannot access /organizer or /gatekeeper routes
- [ ] Back button works correctly

#### Organizer Routing
- [ ] Splash screen routes to /organizer after login
- [ ] All organizer-specific screens accessible
- [ ] Cannot access /attendee or /gatekeeper routes
- [ ] Back button works correctly

#### Gatekeeper Routing
- [ ] Splash screen routes to /gatekeeper after login
- [ ] All gatekeeper-specific screens accessible
- [ ] Cannot access /attendee or /organizer routes
- [ ] Back button works correctly

### 2. Input Validation

#### Event Creation Form
- [ ] Empty event name shows error
- [ ] Empty description shows error
- [ ] Past date/time shows error
- [ ] Empty location shows error
- [ ] Non-numeric capacity shows error
- [ ] Negative capacity shows error
- [ ] Non-numeric price shows error
- [ ] Negative price shows error
- [ ] All fields required before submission

#### Sign Up Form
- [ ] Empty email shows error
- [ ] Invalid email format shows error
- [ ] Empty password shows error
- [ ] Password < 6 characters shows error
- [ ] Empty role selection shows error
- [ ] Duplicate email shows error

### 3. Real-Time Updates

#### Capacity Dashboard
- [ ] Organizer sees live capacity updates
- [ ] Bar color changes (green → red) as capacity fills
- [ ] Percentage text updates
- [ ] Updates within 1 second of ticket status change

#### Ticket Status Updates
- [ ] Attendee sees real-time ACTIVE → USED transition
- [ ] Entry timestamp displays immediately
- [ ] Gatekeeper name displays immediately
- [ ] Euclidean distance metric displays

### 4. Error Handling UI

#### Network Errors
- [ ] "No internet connection" message clear
- [ ] Retry button present
- [ ] Handles timeout gracefully

#### Permission Errors
- [ ] Camera permission denied shows clear message
- [ ] "Allow camera" button navigates to settings
- [ ] Graceful fallback if not permitted

#### Validation Errors
- [ ] Form errors clear and specific
- [ ] Error messages in red
- [ ] Highlight problematic field
- [ ] Clear recovery path

---

## Performance Tests

### 1. Load Testing

#### Scenarios
```
SCENARIO 1: Large Event Capacity
- Event with 1000 capacity
- 800 tickets booked
- Test: Can user still browse event?
- Expected: < 2 second load time

SCENARIO 2: Multiple Concurrent Verifications
- 5 gatekeepers verifying simultaneously
- Test: All transactions succeed without race conditions
- Expected: All marked USED correctly

SCENARIO 3: Organizer Dashboard with Many Events
- 100 events created by organizer
- Test: Dashboard loads and is responsive
- Expected: < 3 second load time
```

### 2. Latency Measurements

| Operation | Target | Actual |
|-----------|--------|--------|
| Face registration | < 3s | ___ |
| Face verification | < 2s | ___ |
| Firestore query | < 1s | ___ |
| Real-time update | < 500ms | ___ |
| Event creation | < 2s | ___ |
| Ticket booking | < 1s | ___ |

---

## Security Tests

### 1. Authentication & Authorization

#### Tests
- [ ] Cannot access other user's tickets
- [ ] Cannot access other organizer's events
- [ ] Gatekeeper cannot verify for unassigned event
- [ ] Cannot modify tickets directly (only through transactions)
- [ ] Session timeout after 30 min inactivity
- [ ] Logout clears all local auth state

### 2. Data Protection

#### Tests
- [ ] Raw landmarks never transmitted over HTTP
- [ ] Only encrypted landmarks stored in Firestore
- [ ] SHA-256 hash immutable (verified on retrieval)
- [ ] Encryption key unique per ticket
- [ ] Decryption fails with wrong key

### 3. Privacy

#### Tests
- [ ] Gatekeeper cannot see attendee photos
- [ ] Gatekeeper cannot access personal info (only for verification)
- [ ] Organizer cannot see raw biometric data
- [ ] Audit logs don't expose facial landmarks
- [ ] Event attendee list doesn't show face data

---

## Device-Specific Tests

### Android

#### Target Devices
- [ ] Android 7 (API 24)
- [ ] Android 10 (API 29)
- [ ] Android 14 (API 34)

#### Tests
- [ ] Camera permissions request works
- [ ] Face detection works accurately
- [ ] QR code scanning works
- [ ] Firestore synchronization reliable
- [ ] Battery consumption acceptable
- [ ] Memory management good (no leaks)

### iOS

#### Target Devices
- [ ] iPhone 11 (iOS 15)
- [ ] iPhone 12 (iOS 16)
- [ ] iPhone 14 (iOS 17)
- [ ] iPhone 15 Pro (iOS 18)

#### Tests
- [ ] Camera permissions request works
- [ ] Face detection works accurately
- [ ] QR code scanning works
- [ ] Firestore synchronization reliable
- [ ] Battery consumption acceptable
- [ ] Home indicator not interfering

---

## Makeup Robustness Tests

### Calibration Procedure

1. **Collect Test Subjects**: Minimum 10 people, diverse ethnicities
2. **Baseline Registration**: Each person registers face with NO makeup
3. **Makeup Variations**: Each person tries verification with:
   - Light makeup (foundation only)
   - Medium makeup (+ eyeshadow, eyeliner)
   - Heavy makeup (+ contour, blush, lipstick)
   - Different lighting conditions
   - Different angles (15°, 30°)

4. **Record Results**:
   ```
   Subject,Makeup,Distance,Result,Notes
   John,None,0.08,MATCH,Baseline
   John,Light,0.12,MATCH,Foundation applied
   John,Medium,0.16,MATCH,Eyeshadow, liner
   John,Heavy,0.19,REJECT,Distance exceeded threshold
   Jane,None,0.09,MATCH,Baseline
   Jane,Light,0.11,MATCH,Foundation applied
   ```

5. **Analysis**:
   - Calculate average distance per makeup level
   - Identify subjects with highest distances
   - Check if 0.18 threshold is appropriate
   - Document any rejections

6. **Recommendation**:
   - If median heavy makeup distance < 0.18: ACCEPT threshold
   - If 1-2 outliers > 0.18: Adjust to 0.19-0.20
   - If many rejections > 0.20: Increase threshold or improve normalization

---

## Regression Testing Checklist

After each code change, run:

- [ ] All unit tests pass
- [ ] Sign up flow works for all roles
- [ ] Event creation works
- [ ] Event booking works
- [ ] Gatekeeper verification works
- [ ] Real-time updates work
- [ ] No console errors
- [ ] No memory leaks detected
- [ ] No new linting warnings

---

## Test Report Template

```
PROJECT: Antigravity Biometric Ticketing
TEST DATE: [DATE]
TESTER: [NAME]
BUILD VERSION: [VERSION]

SUMMARY:
- Total Tests: ___
- Passed: ___
- Failed: ___
- Skipped: ___
- Pass Rate: ___%

FAILED TESTS:
1. [Test Name]
   - Expected: [Description]
   - Actual: [Description]
   - Severity: [Critical/Major/Minor]
   - Recommendation: [Fix/Workaround/Accept]

OBSERVATIONS:
- [Any observations about behavior, performance, edge cases]

SIGN-OFF:
- Tester: _________ Date: _______
- Manager: ________ Date: _______
```

---

## Continuous Testing

### Pre-Commit
```bash
flutter test              # Run all unit tests
flutter analyze           # Check code quality
```

### Pre-Release
```bash
flutter test --coverage   # Generate coverage report
flutter build apk         # Build release APK
flutter build ios         # Build release IPA
```

### Post-Deployment
- [ ] Monitor Firebase Crashlytics daily
- [ ] Review user feedback on app stores
- [ ] Test critical flows on production weekly
- [ ] Monitor Firestore performance metrics
- [ ] Track biometric verification success rate

---

**Last Updated**: [Current Date]
**Version**: 1.0
**Status**: Testing Protocol Active
