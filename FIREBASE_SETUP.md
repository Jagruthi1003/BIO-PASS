# BIOPASS - Firebase Setup & Complete Execution Guide

## 📋 Firebase Collections Structure

### 1. **users** Collection
Stores user account information with role-based access control.

**Document ID**: `{uid}` (Firebase Auth UID)

**Fields**:
```
{
  "uid": String,           // Firebase Auth UID
  "email": String,         // User email
  "name": String,          // Full name
  "role": String,          // "attendee" | "organizer" | "gatekeeper"
  "createdAt": Timestamp,  // Account creation date
  "lastLogin": Timestamp   // Last login date
}
```

**Example**:
```
uid: "user123abc"
├── uid: "user123abc"
├── email: "john@example.com"
├── name: "John Doe"
├── role: "attendee"
├── createdAt: 2024-03-01 10:00:00
└── lastLogin: 2024-03-03 15:30:00
```

---

### 2. **events** Collection
Stores event details created by organizers.

**Document ID**: `{eventId}` (Auto-generated or custom)

**Fields**:
```
{
  "id": String,                    // Event ID
  "name": String,                  // Event name
  "description": String,           // Event description
  "location": String,              // Event location
  "eventDate": Timestamp,          // Date and time of event
  "organizerId": String,           // UID of organizer
  "capacity": Integer,             // Maximum attendees
  "createdAt": Timestamp           // Creation date
}
```

**Example**:
```
id: "evt_tech_2024_001"
├── id: "evt_tech_2024_001"
├── name: "Tech Conference 2024"
├── description: "Annual technology summit"
├── location: "Convention Center, New York"
├── eventDate: 2024-05-15 09:00:00
├── organizerId: "org123abc"
├── capacity: 500
└── createdAt: 2024-03-01 08:00:00
```

---

### 3. **tickets** Collection
Stores ticket information with face landmarks and ZK proofs.

**Document ID**: `{ticketId}` (Auto-generated)

**Fields**:
```
{
  "id": String,                          // Ticket ID
  "eventId": String,                     // Reference to event
  "attendeeId": String,                  // UID of attendee
  "attendeeName": String,                // Attendee name
  "attendeeEmail": String,               // Attendee email
  "faceLandmarks": Array<Double>,        // 68-point face landmarks [x1, y1, x2, y2, ...]
  "zkProof": String,                     // ZK proof (SHA256 hash of landmarks)
  "isRegistered": Boolean,               // Registration completion status
  "isVerified": Boolean,                 // Verification status (used at gate)
  "registrationStatus": String,          // "pending" | "registered" | "verified"
  "verificationMessage": String,         // Message from verification process
  "createdAt": Timestamp,                // Ticket creation date
  "usedAt": Timestamp (optional)         // When ticket was used for entry
}
```

**Example**:
```
id: "ticket_abc123def456"
├── id: "ticket_abc123def456"
├── eventId: "evt_tech_2024_001"
├── attendeeId: "user123abc"
├── attendeeName: "John Doe"
├── attendeeEmail: "john@example.com"
├── faceLandmarks: [245.5, 310.2, 268.3, 298.1, 290.7, 315.4, ...]  // 136 values (68 points × 2)
├── zkProof: "a3b4c5d6e7f8g9h0i1j2k3l4m5n6o7p8q9r0s1t2u3v4w5x6y7z8"
├── isRegistered: true
├── isVerified: false
├── registrationStatus: "registered"
├── verificationMessage: null
├── createdAt: 2024-03-02 14:30:00
└── usedAt: null
```

---

## 🔐 Firebase Security Rules

Add these security rules to your Firestore Database:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only read/write their own documents
    match /users/{uid} {
      allow read, write: if request.auth.uid == uid;
    }
    
    // Events: Organizers can create/update their own, others can read
    match /events/{document=**} {
      allow read: if request.auth != null;
      allow create: if request.auth != null && request.resource.data.organizerId == request.auth.uid;
      allow update, delete: if request.auth != null && resource.data.organizerId == request.auth.uid;
    }
    
    // Tickets: Authenticated users can read, attendees can create
    match /tickets/{document=**} {
      allow read: if request.auth != null;
      allow create: if request.auth != null && request.resource.data.attendeeId == request.auth.uid;
      allow update: if request.auth != null && (resource.data.attendeeId == request.auth.uid || 
                      get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == "gatekeeper");
    }
  }
}
```

---

## 📦 Project File Structure

```
bio_pass/
├── lib/
│   ├── main.dart                        # Main app entry point
│   ├── models/
│   │   ├── event.dart                   # Event model
│   │   ├── ticket.dart                  # Ticket model
│   │   └── user.dart                    # User model
│   ├── services/
│   │   ├── auth_service.dart            # Firebase Auth operations
│   │   ├── event_service.dart           # Event & Ticket CRUD operations
│   │   └── gatekeeper_service.dart      # Gatekeeper operations (if exists)
│   ├── screens/
│   │   ├── splash_screen.dart           # App loading screen
│   │   ├── auth_screen.dart             # Login/Signup screen
│   │   ├── attendee_dashboard.dart      # Attendee main screen
│   │   ├── face_registration_screen.dart # Face capture & registration
│   │   ├── organizer_dashboard.dart     # Organizer main screen + analytics
│   │   ├── gatekeeper_screen.dart       # Entry verification screen
│   │   ├── create_event_screen.dart     # Event creation screen
│   │   └── event_entry_screen.dart      # Event entry details
│   └── zk/
│       └── zk_engine.dart               # ZK proof generation & verification
├── pubspec.yaml                         # Flutter dependencies
├── android/                             # Android native code
├── ios/                                 # iOS native code
└── FIREBASE_SETUP.md                    # This file

```

---

## 🚀 Complete Setup & Execution Steps

### **Step 1: Prerequisites**

1. **Install Flutter** (if not already installed)
   ```bash
   # Check Flutter installation
   flutter --version
   
   # If not installed, download from: https://flutter.dev/docs/get-started/install
   ```

2. **Install Dart SDK** (usually comes with Flutter)
   ```bash
   dart --version
   ```

3. **Install Android Studio** and/or **Xcode** (for mobile development)
   ```bash
   flutter doctor
   ```

4. **Create Firebase Project**
   - Go to [Firebase Console](https://console.firebase.google.com/)
   - Create a new project named "biopass"
   - Enable Firebase Authentication (Email/Password)
   - Create Firestore Database (Start in test mode for development)

---

### **Step 2: Clone/Setup Project**

```bash
# Navigate to project directory
cd c:\bio_pass

# Install Flutter dependencies
flutter pub get

# Verify dependencies
flutter pub list

```

---

### **Step 3: Configure Firebase**

#### **For Android**:

1. Download `google-services.json` from Firebase Console
2. Place it in: `android/app/google-services.json`
3. Ensure `android/build.gradle` has:
   ```gradle
   buildscript {
     dependencies {
       classpath 'com.google.gms:google-services:4.3.15'
     }
   }
   ```

4. Ensure `android/app/build.gradle` has:
   ```gradle
   apply plugin: 'com.google.gms.google-services'
   ```

#### **For iOS**:

1. Download `GoogleService-Info.plist` from Firebase Console
2. Place it in Xcode: `ios/Runner/` directory
3. Run: 
   ```bash
   cd ios && pod install && cd ..
   ```

#### **For macOS/Linux/Web**:
Configure accordingly through Firebase Console for each platform.

---

### **Step 4: Update pubspec.yaml**

Ensure all dependencies are correct:

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^3.6.0
  firebase_auth: ^5.3.1
  cloud_firestore: ^5.4.4
  camera: ^0.11.0
  google_mlkit_face_detection: ^0.10.0
  crypto: ^3.0.3
  permission_handler: ^12.0.1
  image: ^4.1.0
  intl: ^0.19.0
```

Run:
```bash
flutter pub get
flutter pub upgrade
```

---

### **Step 5: Configure Permission Files**

#### **Android (`android/app/src/main/AndroidManifest.xml`)**:
```xml
<!-- Add these permissions -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

#### **iOS (`ios/Runner/Info.plist`)**:
```xml
<!-- Add these keys -->
<key>NSCameraUsageDescription</key>
<string>We need access to your camera for face registration and verification</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photo library for profile pictures</string>
```

---

### **Step 6: Initialize Firebase in Code**

Ensure `main.dart` has Firebase initialization:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}
```

---

### **Step 7: Run the Application**

#### **For Android**:
```bash
# Build and run on connected Android device
flutter run -d android

# Or specify device:
adb devices  # List connected devices
flutter run -d <device_id>
```

#### **For iOS** (macOS only):
```bash
# Install pods
cd ios && pod install && cd ..

# Run on simulator
open -a Simulator
flutter run -d iPhone

# Or on connected device
flutter run -d <device_id>
```

#### **For Web**:
```bash
# Enable web support first
flutter config --enable-web

# Run on web
flutter run -d chrome
```

---

### **Step 8: Firebase Initialization (First Time)**

1. Start the app
2. Click **"Sign Up"**
3. Create an organizer account with:
   - Email: `organizer@example.com`
   - Password: `Password123!`
   - Name: `Event Organizer`
   - Role: `organizer`

4. Create an attendee account with:
   - Email: `attendee@example.com`
   - Password: `Password123!`
   - Name: `John Attendee`
   - Role: `attendee`

5. Create a gatekeeper account with:
   - Email: `gatekeeper@example.com`
   - Password: `Password123!`
   - Name: `Gate Keeper`
   - Role: `gatekeeper`

---

## 🎯 User Journey & Workflows

### **Attendee Flow**:
1. **Sign Up** → Create account with "attendee" role
2. **View Events** → Browse available events on Attendee Dashboard
3. **Register for Event** → Tap "Register with Face"
4. **Grant Permission** → Allow camera access
5. **Capture Face** → Take face photo
6. **ZK Proof Generation** → System generates ZK proof from landmarks
7. **Register** → Ticket created with face landmarks and ZK proof
8. **View Ticket** → See ticket ID and registration status
9. **At Gate** → Present for face verification

### **Organizer Flow**:
1. **Sign Up** → Create account with "organizer" role
2. **Create Event** → Fill event details and set capacity
3. **View Events** → See all created events
4. **View Analytics** → Check registration metrics:
   - Total registered attendees
   - Verification rate
   - Entry rate
5. **View Tickets** → Monitor ticket statuses (Pending/Verified/Used)
6. **Event Management** → Edit or delete events

### **Gatekeeper Flow**:
1. **Sign In** → Access Gatekeeper Dashboard
2. **Scan Ticket ID** → Enter or scan ticket ID
3. **Locate Attendee** → System fetches ticket and attendee details
4. **Capture Face** → Take photo at gate entrance
5. **ZK Verification** → Compare captured landmarks with registered proof
6. **Result**:
   - ✅ **Match** → "Ticket Used" + Entry Granted
   - ❌ **No Match** → "Face does not match" + Entry Denied
7. **Mark as Used** → Ticket marked with timestamp

---

## 🔍 Testing Checklist

### **Test Scenarios**:

- [ ] **Authentication**
  - [ ] Signup with valid email
  - [ ] Signup with invalid email (should fail)
  - [ ] Login with correct credentials
  - [ ] Login with wrong password (should fail)
  - [ ] Logout functionality

- [ ] **Attendee Registration**
  - [ ] View all events
  - [ ] Request camera permission
  - [ ] Capture face and generate landmarks
  - [ ] Ticket creation with ZK proof
  - [ ] View registered tickets with status

- [ ] **Organizer Management**
  - [ ] Create new event
  - [ ] View all created events
  - [ ] See analytics and metrics
  - [ ] View all registered attendees
  - [ ] Monitor verification status

- [ ] **Gatekeeper Verification**
  - [ ] Find ticket by ID
  - [ ] Capture face at gate
  - [ ] Verify face against registered landmarks
  - [ ] Mark ticket as used
  - [ ] Handle face mismatch scenarios

---

## 📊 Database Queries Reference

### **Attendee's Tickets**:
```dart
_firestore
  .collection('tickets')
  .where('attendeeId', isEqualTo: userId)
  .get()
```

### **Event's Registered Attendees**:
```dart
_firestore
  .collection('tickets')
  .where('eventId', isEqualTo: eventId)
  .where('isRegistered', isEqualTo: true)
  .get()
```

### **Unverified Tickets for Event**:
```dart
_firestore
  .collection('tickets')
  .where('eventId', isEqualTo: eventId)
  .where('isRegistered', isEqualTo: true)
  .where('isVerified', isEqualTo: false)
  .get()
```

### **Organizer's Events**:
```dart
_firestore
  .collection('events')
  .where('organizerId', isEqualTo: orgId)
  .get()
```

---

## 🐛 Troubleshooting

### **Issue**: Firebase not initializing
**Solution**:
```bash
flutter clean
flutter pub get
flutter run
```

### **Issue**: Camera permission denied
**Solution**:
- Android: `adb shell pm grant com.example.bio_pass android.permission.CAMERA`
- iOS: Go to Settings → Privacy → Camera → Grant permission

### **Issue**: Face detection not working
**Solution**:
- Ensure good lighting
- Face should be clearly visible
- Download ML Kit face detection model (first time launch takes time)

### **Issue**: Firestore read/write fails
**Solution**:
- Check Firebase Security Rules
- Verify user is authenticated
- Check internet connection
- Review Firestore quota limits

---

## 📞 Support & Resources

- **Flutter Documentation**: https://flutter.dev/docs
- **Firebase Documentation**: https://firebase.google.com/docs
- **Google ML Kit**: https://developers.google.com/ml-kit
- **ZK Proofs**: snarkjs library documentation

---

## ✅ Final Checklist

Before deployment:

- [ ] All dependencies installed and updated
- [ ] Firebase project created and configured
- [ ] Google Services JSON/Plist configured
- [ ] Android manifest permissions added
- [ ] iOS Info.plist permissions added
- [ ] Firebase Firestore rules configured
- [ ] Test accounts created
- [ ] All screens tested on device
- [ ] Face recognition working properly
- [ ] ZK proof generation verified
- [ ] Ticket verification tested
- [ ] Analytics working correctly

---

**Last Updated**: March 2024
**Version**: 1.0.0
**Status**: Ready for Testing
