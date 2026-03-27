# Antigravity Deployment Checklist

## Pre-Deployment Phase

### 1. Code Compilation & Quality Assurance
- [x] All new screens compile without errors (organizer_dashboard_new.dart, attendee_dashboard_new.dart, gatekeeper_verification_screen.dart, zk_face_registration_screen_new.dart)
- [x] All core services compile (enhanced_event_service.dart, face_biometric_service.dart, qr_code_service.dart)
- [x] All data models compile (user.dart, event.dart, ticket.dart)
- [x] Routing system updated for all three roles in main.dart
- [x] CreateEventScreen updated with ticket price field and proper EventService calls
- [ ] Run `flutter pub get` to fetch all dependencies
- [ ] Run `flutter analyze` to check for remaining lint issues
- [ ] Run `flutter clean && flutter build apk --release` for Android
- [ ] Run `flutter build ios --release` for iOS

### 2. Dependencies Verification
- [x] Added qr_flutter: ^4.1.0 for QR code generation
- [x] Added google_mlkit_commons: ^0.7.0 for ML Kit utilities
- [x] Verified firebase_core, firebase_auth, cloud_firestore versions
- [x] Verified camera plugin version
- [x] Verified google_mlkit_face_detection version
- [ ] Run `flutter pub outdated` to check for updates
- [ ] Review dependency compatibility across platforms

### 3. Firebase Configuration
- [ ] Create Firebase project
- [ ] Add Android app to Firebase:
  - [ ] Download google-services.json
  - [ ] Place in android/app/
  - [ ] Configure package name
- [ ] Add iOS app to Firebase:
  - [ ] Download GoogleService-Info.plist
  - [ ] Place in ios/Runner/
  - [ ] Configure bundle ID
- [ ] Enable Authentication methods:
  - [ ] Email/Password
- [ ] Create Firestore database:
  - [ ] Set location (recommended: us-central1)
  - [ ] Choose production mode
- [ ] Configure Firestore collections:
  - [ ] users
  - [ ] events
  - [ ] tickets
  - [ ] verification_audit
  - [ ] gatekeeper_permissions

### 4. Firestore Security Rules
- [ ] Implement role-based access control rules
- [ ] Test user isolation (users can't read other users' data)
- [ ] Test organizer permissions (can only modify own events)
- [ ] Test gatekeeper restrictions (can only verify for assigned events)
- [ ] Test audit log write-only access
- [ ] Test ticket status transition restrictions (ACTIVE→USED only)

### 5. Platform-Specific Setup

#### Android
- [ ] Update package name in android/app/build.gradle
- [ ] Configure signing keys
- [ ] Update minSdkVersion (minimum 21 for ML Kit)
- [ ] Test camera permissions on Android 6.0+
- [ ] Test location permissions if used
- [ ] Configure ProGuard rules in proguard-rules.pro

#### iOS
- [ ] Update bundle identifier in Xcode
- [ ] Configure code signing certificate
- [ ] Update iOS deployment target (minimum 11.0 for ML Kit)
- [ ] Add NSCameraUsageDescription to Info.plist
- [ ] Add NSLocationWhenInUseUsageDescription if needed
- [ ] Test on real device (simulator has limited camera support)

### 6. ML Kit Face Detection Calibration

#### Landmark Validation
- [ ] Verify that Google ML Kit returns sufficient landmarks
- [ ] Test landmark indices:
  - [ ] Nose tip (index 30 in normalized output)
  - [ ] Left eye (indices 36-41)
  - [ ] Right eye (indices 42-47)
  - [ ] Face outline (indices 0-16)
- [ ] Verify inter-ocular distance calculation accuracy

#### Euclidean Distance Threshold Tuning (0.18)
- [ ] Test perfect match (same person, same conditions): distance < 0.05
- [ ] Test good match (same person, different lighting): distance 0.05-0.10
- [ ] Test acceptable match (same person, makeup): distance 0.10-0.18
- [ ] Test rejection (different person): distance > 0.18
- [ ] Create comprehensive calibration dataset with 20+ users
- [ ] Test makeup robustness:
  - [ ] Light makeup (foundation only)
  - [ ] Medium makeup (+ eyeshadow, eyeliner)
  - [ ] Heavy makeup (+ contour, blush, lipstick)
  - [ ] Different makeup brands
- [ ] Test lighting variations:
  - [ ] Indoor fluorescent (cool lighting)
  - [ ] Indoor warm lighting
  - [ ] Outdoor daylight
  - [ ] Low light conditions (if applicable)
- [ ] Test at various angles:
  - [ ] Face directly to camera
  - [ ] 15° rotation
  - [ ] 30° rotation
- [ ] Document threshold adjustment if needed (provide recommendation)

### 7. Biometric Pipeline Testing

#### Face Capture & Normalization
- [ ] Test auto-capture detection (face aligned in guide frame)
- [ ] Test landmark extraction with multiple face sizes
- [ ] Verify normalization (nose-centering + inter-ocular scaling)
- [ ] Test with glasses (occlusion handling)
- [ ] Test with beards/facial hair

#### Hash Generation & Verification
- [ ] Test SHA-256 hash determinism (same face → same hash)
- [ ] Test hash sensitivity (makeup slightly changes hash)
- [ ] Verify encrypted vector storage (XOR encryption working)
- [ ] Test hash comparison in verification

#### End-to-End Verification Flow
- [ ] Face register at ticket booking
- [ ] Gatekeeper verifies at entry
- [ ] Confirm distance calculation accuracy
- [ ] Confirm atomic transaction prevents double-entry

### 8. Ticket Lifecycle Testing

#### Ticket States
- [ ] ACTIVE ticket: newly booked, ready for entry
- [ ] Transition ACTIVE → USED: face verification succeeds
- [ ] USED ticket: shows entry timestamp and gatekeeper name
- [ ] CANCELLED ticket: attendee cancels or organizer cancels
- [ ] Prevent re-entry: USED ticket cannot be verified again

#### Capacity Management
- [ ] Event with capacity 10 allows exactly 10 bookings
- [ ] 11th booking attempt shows "event full" error
- [ ] Cancellation releases ticket count
- [ ] Capacity bar updates in real-time

### 9. Role-Based Routing Testing

#### Attendee Flow
- [ ] Sign up as attendee
- [ ] Navigate to /attendee route
- [ ] Browse events tab shows available events
- [ ] Book ticket with capacity check
- [ ] Face registration screen auto-appears
- [ ] My tickets tab shows booked tickets
- [ ] Ticket status updates real-time when gatekeeper verifies

#### Organizer Flow
- [ ] Sign up as organizer
- [ ] Navigate to /organizer route
- [ ] Create event with name, description, date, location, capacity, price
- [ ] My events tab shows created events
- [ ] Edit event details
- [ ] Assign gatekeeper by email
- [ ] Gatekeepers tab shows assigned gatekeepers
- [ ] Remove gatekeeper with confirmation
- [ ] Capacity dashboard shows real-time stats

#### Gatekeeper Flow
- [ ] Organizer assigns gatekeeper by email
- [ ] Gatekeeper logs in and navigates to /gatekeeper route
- [ ] Scan QR code or enter ticket ID
- [ ] Face verification screen activates with rear camera
- [ ] Live face detection with guide overlay
- [ ] Euclidean distance calculation shows distance metric
- [ ] Success: ticket marked USED, entry granted
- [ ] Failure: distance too high, entry denied
- [ ] Both attempts logged in audit trail

### 10. Data Synchronization & Real-Time Updates

#### Firestore Listeners
- [ ] Attendee dashboard updates when gatekeeper verifies ticket
- [ ] Ticket status changes from ACTIVE to USED
- [ ] Entry timestamp displays
- [ ] Gatekeeper name displays
- [ ] Euclidean distance metric displays
- [ ] Organizer dashboard updates capacity in real-time
- [ ] Audit logs populated for all verification attempts

### 11. Error Handling & Edge Cases

#### Network Errors
- [ ] No network: show error message with retry button
- [ ] Firestore timeout: implement exponential backoff
- [ ] Authentication token expired: prompt re-login
- [ ] Permission denied: clear error message

#### User Input Validation
- [ ] Empty event name: show error
- [ ] Negative capacity: show error
- [ ] Invalid date (past): show error
- [ ] Invalid email format: show error
- [ ] Duplicate event name: allow (no restriction)

#### Camera & Biometric Errors
- [ ] Camera permission denied: show permission request screen
- [ ] Camera unavailable: graceful fallback
- [ ] No face detected: prompt user to adjust position
- [ ] Multiple faces detected: use largest face
- [ ] Face detection timeout: show error and retry

#### Ticket Verification Edge Cases
- [ ] Ticket not found: show error
- [ ] Ticket already USED: prevent re-entry
- [ ] Ticket CANCELLED: reject entry
- [ ] Missing biometric data: reject entry
- [ ] Decryption failure: log error and reject
- [ ] Double-entry attempt: atomic transaction prevents it

### 12. Security Validation

#### Authentication
- [ ] User cannot access other user's tickets
- [ ] Organizer cannot modify other organizer's events
- [ ] Gatekeeper cannot verify for unassigned events
- [ ] Session tokens expire after inactivity
- [ ] Logout clears cached credentials

#### Data Protection
- [ ] Raw landmarks never transmitted or stored
- [ ] Only normalized landmarks encrypted and stored
- [ ] SHA-256 hash is immutable commitment
- [ ] Encrypted landmarks use strong XOR (upgrade path to AES-256)
- [ ] Audit logs are write-only

#### Privacy
- [ ] No personal biometric data shared
- [ ] Face photos not stored (only landmarks)
- [ ] Gatekeeper cannot see attendee photos
- [ ] Verification results don't leak identity

### 13. Performance Testing

#### Load Testing
- [ ] Event with 100 booked tickets: all load correctly
- [ ] Organizer dashboard with 50 events: responsive
- [ ] Capacity dashboard updates smoothly
- [ ] Multiple concurrent verifications: transactions prevent errors

#### Latency Testing
- [ ] Face registration: < 3 seconds
- [ ] Ticket verification: < 2 seconds
- [ ] Firestore queries: < 1 second
- [ ] Real-time updates: < 500ms propagation

#### Memory Usage
- [ ] App startup: < 100MB
- [ ] Face detection: < 50MB additional
- [ ] Long session: no memory leaks
- [ ] Camera stream: handles properly

### 14. Accessibility & Localization

#### Accessibility
- [ ] All buttons have proper labels
- [ ] Color contrast meets WCAG standards
- [ ] Large touch targets (minimum 48x48dp)
- [ ] Text scaling supported
- [ ] Screen reader compatible (if applicable)

#### Localization
- [ ] All strings in strings/translation files (if needed)
- [ ] Date/time formatting respects locale
- [ ] Error messages are clear and helpful

### 15. Testing Scenarios

#### End-to-End Attendee Scenario
```
1. New user signs up as attendee (email: attendee@example.com)
2. Browse events tab
3. Find "Tech Conference 2024" with 100 capacity, $25 price
4. Click "Book Ticket"
5. Face registration screen appears
6. Align face in guide frame, auto-capture
7. Success: ticket created with ACTIVE status
8. My tickets tab shows ticket with QR code
9. Share ticket ID with gatekeeper
10. Gatekeeper scans QR → Face verification
11. Euclidean distance: 0.12 (match!)
12. Ticket marked USED, entry timestamp recorded
13. Attendee sees real-time update: USED status, timestamp, gatekeeper name
```

#### End-to-End Organizer Scenario
```
1. New user signs up as organizer
2. Create event: "Flutter Summit", 2024-12-15, location "NYC", capacity 200, price $49
3. Event created successfully
4. My events shows "Flutter Summit"
5. Capacity bar shows 0/200
6. Click "Assign Gatekeeper"
7. Enter gatekeeper@example.com
8. Gatekeeper assigned successfully
9. Real-time updates: as attendees book, capacity bar fills
10. Final capacity: 150/200 (75% filled)
```

#### Gatekeeper Verification Scenario
```
1. Organizer assigns gatekeeper@example.com to "Flutter Summit"
2. Gatekeeper logs in, navigates to /gatekeeper
3. Receive ticket ID: "FLUTTER_SUMMIT_0001"
4. Enter ticket ID in QR input
5. System loads ticket details: attendee name, event, date
6. Click "Verify Face"
7. Rear camera activates with face guide overlay
8. Align face, auto-capture
9. Landmark extraction, normalization, distance calculation
10. Distance: 0.14 (< 0.18 threshold) → MATCH!
11. Atomic transaction: ticket updated to USED
12. Success screen: "Entry Granted! John Doe"
13. Audit log created: timestamp, distance, status
14. Attendee app shows real-time update: USED status
```

## Deployment Phase

### 1. Pre-Release Beta Testing
- [ ] Internal testing with team (all three roles)
- [ ] 10-20 beta testers (external)
- [ ] Collect feedback on UX/performance
- [ ] Bug fixes based on feedback

### 2. Release Build Creation
- [ ] Update version in pubspec.yaml
- [ ] Update build number
- [ ] Create release notes
- [ ] Generate signed APK for Android
- [ ] Generate signed IPA for iOS

### 3. App Store Submissions
- [ ] Google Play Store submission:
  - [ ] Create app listing
  - [ ] Upload screenshots (min 2, max 8)
  - [ ] Write compelling description
  - [ ] Set privacy policy URL
  - [ ] Set app content rating
  - [ ] Upload signed APK
  - [ ] Submit for review
- [ ] Apple App Store submission:
  - [ ] Create app listing in App Store Connect
  - [ ] Upload screenshots (iPhone, iPad)
  - [ ] Write description and keywords
  - [ ] Set privacy policy URL
  - [ ] Configure app capabilities (camera)
  - [ ] Upload signed IPA
  - [ ] Submit for review

### 4. Deployment Configuration
- [ ] Firebase project settings verified
- [ ] Firestore security rules deployed
- [ ] Backend services running (if applicable)
- [ ] Email verification enabled
- [ ] Password reset configured
- [ ] Session timeout configured (recommended: 30 minutes)

## Post-Deployment Phase

### 1. Monitoring & Observability
- [ ] Set up Firebase Crashlytics
- [ ] Set up Firebase Performance Monitoring
- [ ] Set up Firestore monitoring alerts
- [ ] Set up authentication failure alerts
- [ ] Monitor app store reviews daily for first week

### 2. Maintenance & Support
- [ ] Respond to user feedback within 24 hours
- [ ] Monitor for critical bugs
- [ ] Prepare hotfix for critical issues
- [ ] Schedule weekly reviews of:
  - [ ] Crash reports
  - [ ] User analytics
  - [ ] Performance metrics
  - [ ] Authentication issues

### 3. Future Enhancements
- [ ] Implement liveness detection (blink, head movement)
- [ ] Upgrade to AES-256 encryption
- [ ] Add machine learning model for makeup robustness
- [ ] Implement batch verification reports
- [ ] Add payment gateway integration
- [ ] Implement mobile wallet integration

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Developer | | | |
| QA Lead | | | |
| Product Manager | | | |
| Security Officer | | | |

---

## Notes & Recommendations

### High Priority Fixes Before Launch
1. **ML Kit Calibration**: Euclidean distance threshold (0.18) must be empirically tested with real users and makeup variations
2. **Makeup Robustness**: Test with at least 10 different makeup styles to ensure 0.18 threshold is appropriate
3. **Permission Handling**: Ensure camera permissions request works on both Android 6+ and iOS 11+
4. **Firestore Rules**: Implement and test all security rules before launch

### Medium Priority Optimizations
1. **QR Code UI**: Replace placeholder with actual qr_flutter visual rendering
2. **Face Guide Overlay**: Refine animation and visual feedback
3. **Error Messages**: Translate technical errors to user-friendly messages
4. **Performance**: Profile and optimize landmark extraction on older devices

### Long-Term Improvements
1. **AI/ML Model**: Train custom model for better makeup robustness
2. **Liveness Detection**: Add blink/head movement detection to prevent spoofing
3. **Batch Processing**: Allow organizers to verify multiple attendees at once
4. **Analytics**: Dashboard showing verification statistics, peak times, attendance patterns
5. **Integration**: Connect with ticketing platforms, payment processors, event management systems

---

**Last Updated**: [Current Date]
**Version**: 1.0
**Status**: Pre-Launch Checklist
