# Firebase Setup Quick Reference - 5 Steps to Production

## Step 1: Create Firebase Project (5 minutes)

```
1. Go to https://console.firebase.google.com
2. Click "Create project"
3. Enter name: "bio_pass"
4. Click "Create project"
5. Wait for completion
```

**Save your Project ID** (used later): `bio_pass-xxxxx`

---

## Step 2: Enable Firebase Services (10 minutes)

### Authentication
```
Build → Authentication → Get started → Email/Password → Enable
```

### Firestore Database
```
Build → Firestore Database → Create database → Production mode → Create
```

### Cloud Functions
```
Build → Functions → Get started (automatic after first deployment)
```

---

## Step 3: Configure Email Service (5 minutes)

### Option A: Gmail (Free, for testing)
```bash
1. Go to myaccount.google.com → Security
2. Enable 2-Step Verification
3. Go to myaccount.google.com/apppasswords
4. Select Mail → Your Device
5. Copy the 16-character password
6. Save: GMAIL_PASSWORD = your_16_char_password
```

### Option B: SendGrid (Free tier, production)
```bash
1. Sign up at sendgrid.com
2. Create API Key at Settings → API Keys
3. Enable "Mail Send" permission
4. Copy API Key
5. Save: SENDGRID_API_KEY = your_api_key
```

---

## Step 4: Deploy Cloud Functions (5 minutes)

```bash
# Navigate to functions directory
cd c:\bio_pass\firebase_cloud_functions\functions

# Install dependencies
npm install

# Create .env.local file with credentials
# For Gmail:
echo GMAIL_USER=your_email@gmail.com > .env.local
echo GMAIL_PASSWORD=your_app_password >> .env.local

# OR For SendGrid:
echo SENDGRID_API_KEY=your_sendgrid_key > .env.local
echo SENDGRID_FROM_EMAIL=noreply@yourdomain.com >> .env.local

# Login to Firebase (first time only)
firebase login

# Select your project
firebase use bio_pass

# Deploy
firebase deploy --only functions

# ✅ Copy the Cloud Function URL printed in console
```

**Example URL**: `https://us-central1-bio-pass-xxxxx.cloudfunctions.net/sendOTPEmail`

---

## Step 5: Configure Flutter App (10 minutes)

### 5.1: Add Firebase Credentials

**Android**: `android/app/google-services.json`
```bash
1. Go to Firebase Console → Project Settings
2. Find your Android app
3. Download google-services.json
4. Place in android/app/
```

**iOS**: `ios/Runner/GoogleService-Info.plist`
```bash
1. Go to Firebase Console → Project Settings
2. Find your iOS app
3. Download GoogleService-Info.plist
4. Open ios/Runner.xcworkspace in Xcode
5. Drag GoogleService-Info.plist into Runner folder
```

### 5.2: Update Cloud Function URL

**File**: `lib/services/email_service.dart` (Line ~11)

```dart
// Before:
static const String cloudFunctionUrl = 
    'https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/sendOTPEmail';

// After (replace YOUR_PROJECT_ID with your actual project ID):
static const String cloudFunctionUrl = 
    'https://us-central1-bio-pass-xxxxx.cloudfunctions.net/sendOTPEmail';
```

### 5.3: Update Firebase Options

**File**: `lib/firebase_options.dart`

Replace with your Firebase Web App config from Firebase Console:
```dart
web: FirebaseOptions(
  apiKey: "YOUR_API_KEY_FROM_FIREBASE",
  authDomain: "bio-pass-xxxxx.firebaseapp.com",
  projectId: "bio-pass-xxxxx",
  storageBucket: "bio-pass-xxxxx.appspot.com",
  messagingSenderId: "YOUR_MESSAGING_ID",
  appId: "YOUR_APP_ID",
),
```

### 5.4: Set Production Mode

**File**: `lib/services/email_service.dart` (Line ~17)

```dart
// Change from:
static const bool isDevelopmentMode = true;

// To:
static const bool isDevelopmentMode = false;
```

---

## Testing Verification

```bash
# 1. Build the app
flutter pub get
flutter build apk --debug

# 2. Run the app
flutter run

# 3. Test sign-up:
   - Enter email: your_test_email@gmail.com
   - Click Sign Up
   - Wait for OTP email (check inbox + spam folder)
   - Enter OTP from email
   - Verify success

# 4. Check Cloud Function logs:
firebase functions:log
```

---

## Firebase Console - Key Locations

| Task | Path |
|------|------|
| View Users | Authentication → Users tab |
| View OTP Records | Firestore Database → otp_verification collection |
| Set Security Rules | Firestore Database → Rules tab |
| Monitor Functions | Functions → Logs tab |
| View Errors | Functions → Logs tab (filter by ERROR) |
| Project Settings | ⚙️ (gear icon, top-right) |
| Download Credentials | Project Settings → Service accounts |

---

## Common Firebase URLs

```
Console: https://console.firebase.google.com
Your Project: https://console.firebase.google.com/project/bio-pass-xxxxx
Firestore Data: https://console.firebase.google.com/project/bio-pass-xxxxx/firestore/data
Functions: https://console.firebase.google.com/project/bio-pass-xxxxx/functions
Authentication: https://console.firebase.google.com/project/bio-pass-xxxxx/authentication
```

---

## Environment Variables Reference

### Email Service Configuration

**Gmail `.env.local`**:
```env
GMAIL_USER=your_email@gmail.com
GMAIL_PASSWORD=xxxx_xxxx_xxxx_xxxx (16-char app password)
```

**SendGrid `.env.local`**:
```env
SENDGRID_API_KEY=SG.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
SENDGRID_FROM_EMAIL=noreply@yourdomain.com
```

---

## File Locations Checklist

```
✅ firebase_cloud_functions/functions/sendOTPEmail.js - Already configured
✅ firebase_cloud_functions/functions/.env.local - TODO: Add email credentials
✅ lib/services/email_service.dart - TODO: Update Cloud Function URL
✅ lib/firebase_options.dart - TODO: Update Firebase config
✅ lib/services/auth_service.dart - ✅ Updated
✅ lib/services/otp_service.dart - ✅ Updated
✅ lib/screens/otp_verification_screen.dart - ✅ Updated
✅ android/app/google-services.json - TODO: Download from Firebase
✅ ios/Runner/GoogleService-Info.plist - TODO: Download from Firebase
✅ .gitignore - TODO: Add sensitive files (already should be there)
```

---

## Typical Deployment Timeline

| Phase | Time | Task |
|-------|------|------|
| Setup | 5 min | Create Firebase project |
| Services | 10 min | Enable Auth, Firestore, Functions |
| Email | 5 min | Configure Gmail or SendGrid |
| Functions | 5 min | Deploy Cloud Functions |
| Flutter | 10 min | Update configs and URLs |
| Testing | 10 min | Test sign-up flow |
| **Total** | **45 min** | **From scratch to working!** |

---

## Monitoring Dashboard

After deployment, bookmark these Firebase Console pages:

1. **Firestore Metrics**: `project/firestore/monitor`
   - Watch database read/write rates
   - Monitor storage usage

2. **Function Logs**: `project/functions/logs`
   - Real-time email sending logs
   - Error tracking

3. **Authentication**: `project/authentication/users`
   - Track sign-ups
   - Manage users

4. **Performance**: `project/performance`
   - Monitor latency
   - Track crashes

---

## Support Resources

| Issue | Resource |
|-------|----------|
| Firebase Setup | [Firebase Docs](https://firebase.google.com/docs) |
| Cloud Functions | [Functions Guide](https://firebase.google.com/docs/functions) |
| Firestore | [Firestore Docs](https://firebase.google.com/docs/firestore) |
| Gmail App Password | [Google Support](https://support.google.com/accounts/answer/185833) |
| SendGrid API | [SendGrid Docs](https://docs.sendgrid.com) |
| Flutter Firebase | [Flutter Plugins](https://pub.dev/packages/firebase_core) |
| Troubleshooting | See `COMPLETE_FIREBASE_BACKEND_SETUP.md` |

---

## Emergency Troubleshooting

```bash
# View real-time logs
firebase functions:log --follow

# View recent errors only
firebase functions:log --limit 100 | grep ERROR

# Redeploy functions
firebase deploy --only functions --force

# Check Firebase CLI version
firebase --version

# Logout and login again
firebase logout
firebase login
```

---

## Next Steps After Setup

1. ✅ Complete this setup guide
2. Deploy to Google Play Console
3. Deploy to Apple App Store
4. Set up Crashlytics monitoring
5. Set up Performance monitoring
6. Create support documentation
7. Plan Phase 2 features (SMS, 2FA, etc.)

---

## Final Verification Checklist

```
✅ Firebase project created
✅ Authentication enabled
✅ Firestore database created
✅ Cloud Functions deployed
✅ Email service configured
✅ Flutter app updated with URLs
✅ Firebase credentials added
✅ Test sign-up completed successfully
✅ OTP email received
✅ App verified user successfully
✅ isDevelopmentMode = false for production
✅ Security rules published
✅ TTL policy configured
✅ Monitoring enabled
```

---

**Time to Deploy**: ~45 minutes from start to finish  
**Status**: ✅ Ready for Production  
**Last Updated**: April 2026

**Need help?** See `COMPLETE_FIREBASE_BACKEND_SETUP.md` for detailed instructions
