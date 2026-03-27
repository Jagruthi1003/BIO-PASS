# Antigravity - Build & Deployment Instructions

Complete step-by-step guide for building, testing, and deploying the biometric-powered event ticketing platform.

## Quick Start (Development)

### Prerequisites
```bash
# Check Flutter version (should be 3.22.0+)
flutter --version

# Check Dart version
dart --version

# Ensure Android SDK is installed
flutter doctor
```

### Installation
```bash
# Clone or navigate to project directory
cd c:\bio_pass

# Get all dependencies
flutter pub get

# Check for any issues
flutter analyze

# Run the app
flutter run
```

---

## Development Build

### Android Development Build
```bash
# Build APK for testing
flutter build apk --debug

# Output: build/app/outputs/flutter-apk/app-debug.apk

# Install and run on device
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.example.bio_pass/com.example.bio_pass.MainActivity
```

### iOS Development Build
```bash
# Build for iOS simulator
flutter build ios --debug --simulator

# Or build for physical device
flutter build ios --debug

# Run on physical device
open -a Simulator
flutter run
```

### Web Development Build (Optional)
```bash
# Build for web
flutter build web

# Serve locally
python -m http.server --directory build/web 8000

# Open http://localhost:8000
```

---

## Firebase Setup

### 1. Create Firebase Project
```bash
# Visit https://console.firebase.google.com
# Click "Create Project"
# Name: "Antigravity"
# Disable Google Analytics (optional)
# Click "Create"
```

### 2. Add Android App
```bash
1. In Firebase Console: Click "Add app" → Android
2. App package name: com.example.bio_pass
3. Download google-services.json
4. Copy to android/app/google-services.json
5. SHA-1 certificate:
   - Run: keytool -list -v -keystore ~/.android/debug.keystore
   - Default password: android
   - Copy SHA-1 fingerprint
   - Paste into Firebase console
6. Click "Next" → "Next" → "Continue to console"
```

### 3. Add iOS App
```bash
1. In Firebase Console: Click "Add app" → iOS
2. iOS Bundle ID: com.example.bio_pass
3. Download GoogleService-Info.plist
4. In Xcode: Drag GoogleService-Info.plist into ios/Runner
5. Select "Runner" target
6. Click "Finish"
```

### 4. Enable Authentication
```bash
1. Firebase Console → Authentication
2. Click "Sign-in method"
3. Enable "Email/Password"
4. Click "Save"
```

### 5. Create Firestore Database
```bash
1. Firebase Console → Firestore Database
2. Click "Create database"
3. Start in "Production mode"
4. Select region: us-central1 (or closest to you)
5. Click "Create"
6. Go to "Rules" tab
7. Replace rules with security rules (see SECURITY_RULES.md)
8. Click "Publish"
```

### 6. Deploy Security Rules
```bash
# Install Firebase CLI
npm install -g firebase-tools

# Initialize Firebase in project
firebase init firestore

# Deploy rules
firebase deploy --only firestore:rules
```

---

## Production Build

### Android Release Build

#### Step 1: Create Signed Key
```bash
# Generate signing key (one-time)
keytool -genkey -v -keystore bio_pass.jks -keyalg RSA -keysize 2048 -validity 10000 -alias bio_pass

# Enter information:
# - Keystore password: [CREATE SECURE PASSWORD]
# - Key password: [SAME AS KEYSTORE]
# - First and Last Name: Antigravity
# - Organizational Unit: Engineering
# - Organization: Your Company
# - City/Locality: Your City
# - State: Your State
# - Country: US

# Move to secure location
mv bio_pass.jks android/app/
```

#### Step 2: Configure Gradle
```bash
# Edit android/key.properties
```
```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=bio_pass
storeFile=key.jks
```

#### Step 3: Build Release APK
```bash
flutter build apk --release

# Output: build/app/outputs/flutter-apk/app-release.apk

# Test on physical device
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

#### Step 4: Build App Bundle (For Play Store)
```bash
flutter build appbundle --release

# Output: build/app/outputs/bundle/release/app-release.aab
```

### iOS Release Build

#### Step 1: Update Version
```bash
# Edit pubspec.yaml
version: 1.0.0+1
```

#### Step 2: Configure Code Signing
```bash
# Open ios/Runner.xcworkspace (NOT Runner.xcodeproj)
open ios/Runner.xcworkspace

# In Xcode:
# 1. Select Runner project
# 2. Select Runner target
# 3. Go to "Signing & Capabilities"
# 4. Select development team
# 5. Ensure provisioning profile is selected
```

#### Step 3: Build Release IPA
```bash
flutter build ios --release

# Output: build/ios/iphoneos/Runner.app

# Or build IPA directly
cd ios
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Release -derivedDataPath build

# Extract IPA
cd build/Release-iphoneos
mkdir Payload
mv Runner.app Payload/
zip -r ../Runner.ipa Payload
```

---

## Testing

### Run All Tests
```bash
# Run unit tests
flutter test

# Run with coverage
flutter test --coverage

# Generate coverage report
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Manual Testing Checklist

#### Attendee Flow
```
□ Sign up with valid email/password
□ Select "Attendee" role
□ Browse events tab shows available events
□ Click book ticket on any event
□ Face registration screen appears
□ Face auto-captures when aligned
□ Ticket appears in "My Tickets" with ACTIVE status
□ QR code displays
□ (Have gatekeeper verify in parallel)
□ Real-time update shows USED status
□ Entry timestamp displays
```

#### Organizer Flow
```
□ Sign up with valid email/password
□ Select "Organizer" role
□ Create new event with:
  □ Name, description, date, location
  □ Capacity (any number > 0)
  □ Ticket price (any positive number)
□ Event appears in "My Events" tab
□ Capacity bar shows 0/[capacity]
□ Assign gatekeeper by email
□ Gatekeeper appears in "Gatekeepers" tab
□ As attendees book, capacity bar fills
□ Real-time updates work
```

#### Gatekeeper Flow
```
□ Organizer assigns you as gatekeeper
□ Log in as gatekeeper
□ Navigate to gatekeeper verification screen
□ Enter or scan ticket ID
□ Ticket details load correctly
□ Click "Verify Face"
□ Rear camera activates with guide overlay
□ Face auto-captures when aligned
□ Distance metric displays
□ If match (< 0.18): "Entry Granted" shown
□ If no match: "Face Mismatch" shown
□ Ticket status updates in Firestore
□ Attendee sees real-time update
```

---

## Deployment to App Stores

### Google Play Store

#### Step 1: Prepare App Listing
```bash
1. Go to Google Play Console: https://play.google.com/console
2. Create new application
3. Fill in required fields:
   - App name
   - Short description (80 chars)
   - Full description
   - Screenshots (min 2, max 8, 1080x1920px)
   - Feature graphic (1024x500px)
   - Icon (512x512px)
   - Privacy policy URL
   - Contact email
4. Select app category: Entertainment → Events
5. Content rating: Complete questionnaire
```

#### Step 2: Upload Build
```bash
1. Navigate to: Internal Testing → Releases
2. Click "Create release"
3. Upload app-release.aab (App Bundle)
4. Set version code: 1 (increments with each release)
5. Add release notes
6. Review and save
```

#### Step 3: Submit for Review
```bash
1. Go to "App releases" → "Production"
2. Click "Create release"
3. Upload same bundle
4. Set version code: 2 (or higher)
5. Add detailed release notes
6. Add privacy policy, permissions explanation
7. Click "Review and roll out"
8. Submit for review
9. Wait 2-4 hours for initial review
```

### Apple App Store

#### Step 1: Prepare App Listing
```bash
1. Go to App Store Connect: https://appstoreconnect.apple.com
2. Create new app
3. Fill in required fields:
   - App name
   - Bundle ID: com.example.bio_pass
   - SKU
   - Platform: iOS
4. Fill in app information:
   - Privacy policy URL
   - Category: Entertainment
   - Contact email
   - Demo account (if needed)
5. Add screenshots (iPhone and iPad sizes)
6. Add preview video (optional)
7. Add description, keywords, support URL
```

#### Step 2: Build and Archive
```bash
# In Xcode
1. Select "Any iOS Device (arm64)"
2. Product → Archive
3. Distribute App
4. Select "App Store Connect" distribution
5. Follow wizard to upload
```

#### Step 3: Submit for Review
```bash
1. In App Store Connect: TestFlight → Builds
2. Select latest build
3. Set version string: 1.0
4. Add build notes
5. Click "Submit for Review"
6. Provide review information
7. Submit
8. Wait 24-48 hours for review
```

---

## Version Management

### Update Version
```bash
# Edit pubspec.yaml
version: 1.0.0+1
```

Format: `major.minor.patch+buildNumber`

Example progression:
```
1.0.0+1 (Initial release)
1.0.1+2 (Bug fix)
1.1.0+3 (Minor feature)
2.0.0+4 (Major update)
```

### Update Dependencies
```bash
# Check for outdated packages
flutter pub outdated

# Update specific package
flutter pub upgrade package_name

# Update all packages
flutter pub upgrade

# Clean build
flutter clean
flutter pub get
```

---

## Troubleshooting

### Build Failures

#### Android: "No matching variant"
```bash
# Clear build
flutter clean
flutter pub get

# Rebuild
flutter build apk --release
```

#### iOS: "Pod repo update required"
```bash
# Update CocoaPods
cd ios
rm -rf Pods
rm Podfile.lock
pod repo update
pod install
cd ..

# Rebuild
flutter build ios --release
```

#### Firebase: "google-services.json not found"
```bash
# Ensure google-services.json is in android/app/
ls android/app/google-services.json

# Add to .gitignore if needed
echo "google-services.json" >> android/.gitignore
```

### Runtime Failures

#### Camera permission denied
```
Solution: Go to Settings → Apps → Antigravity → Permissions → Camera → Allow
```

#### Face detection not working
```
Solution: 
1. Ensure ML Kit dependencies installed: flutter pub get
2. Test on physical device (emulator has limited ML Kit support)
3. Check logcat for ML Kit errors
```

#### Firestore connection issues
```
Solution:
1. Check internet connection
2. Verify Firebase project is properly configured
3. Check Firestore security rules
4. Look for permission errors in Firebase Console → Firestore
```

---

## Performance Optimization

### Code Optimization
```bash
# Enable release mode for testing
flutter run --release

# Profile performance
flutter run --profile

# Measure build time
flutter build apk --verbose --release

# Analyze code size
flutter build apk --analyze-size --release
```

### Asset Optimization
```bash
# Compress images
# Use PNG for single-color graphics
# Use WebP for photos (if supported)

# Update pubspec.yaml
assets:
  - assets/images/
  - assets/icons/

# Verify asset loading in logs
I/flutter: Image loaded: assets/images/logo.png
```

### Database Optimization
```
Firestore Best Practices:
- Use indexed queries
- Limit document size < 1MB
- Avoid deep nesting
- Use collection groups for cross-collection queries
- Monitor read/write operations in console
```

---

## CI/CD Integration (Optional)

### GitHub Actions Workflow
```yaml
# .github/workflows/build.yml
name: Build

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.22.0'
      - run: flutter pub get
      - run: flutter test
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v3
        with:
          name: apk
          path: build/app/outputs/flutter-apk/app-release.apk
```

---

## Monitoring & Analytics

### Firebase Crashlytics
```dart
// In main.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  FirebaseOptions? firebaseOptions = DefaultFirebaseOptions.currentPlatform;
  Firebase.initializeApp(options: firebaseOptions);
  
  // Enable Crashlytics
  FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
  
  runApp(const MyApp());
}
```

### Performance Monitoring
```dart
// Track custom events
Future<void> verifyFace() async {
  final trace = FirebasePerformance.instance.newTrace('face_verification');
  await trace.start();
  
  try {
    // Verification logic
  } finally {
    await trace.stop();
  }
}
```

---

## Maintenance Schedule

### Daily (During Launch Week)
- [ ] Monitor Firebase Crashlytics
- [ ] Check app store reviews
- [ ] Verify no spike in errors
- [ ] Monitor Firestore metrics

### Weekly
- [ ] Review analytics
- [ ] Check authentication issues
- [ ] Monitor API errors
- [ ] Test critical flows

### Monthly
- [ ] Update dependencies
- [ ] Review security
- [ ] Optimize database queries
- [ ] Plan next release

### Quarterly
- [ ] Major feature planning
- [ ] Performance profiling
- [ ] UX research
- [ ] Competitive analysis

---

## Support & Documentation

### For Users
- In-app help text for all features
- FAQ: https://example.com/faq
- Email: support@example.com
- Live chat (if available)

### For Developers
- Architecture: See [ANTIGRAVITY_ARCHITECTURE.md](ANTIGRAVITY_ARCHITECTURE.md)
- Testing: See [TESTING.md](TESTING.md)
- Deployment: See [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)
- API Docs: Generated with `dartdoc`

---

## Emergency Rollback

If critical issue detected after release:

```bash
# Identify issue
# Create hotfix branch
git checkout -b hotfix/critical-issue

# Fix code
# Test thoroughly
# Build new APK
flutter build apk --release

# Upload to Play Store as "internal testing"
# Test on real devices
# Promote to production

# For iOS: Build and submit new version
# Apple typically approves hotfixes within 2-4 hours
```

---

**Last Updated**: [Current Date]
**Version**: 1.0
**Maintained By**: Development Team

For questions or issues, contact: dev-team@example.com
