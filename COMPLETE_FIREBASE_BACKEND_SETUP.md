# Complete Firebase Backend Setup & Integration Guide

## Table of Contents
1. [Firebase Project Setup](#firebase-project-setup)
2. [Email Service Configuration](#email-service-configuration)
3. [Firestore Database Setup](#firestore-database-setup)
4. [Cloud Functions Deployment](#cloud-functions-deployment)
5. [Flutter App Configuration](#flutter-app-configuration)
6. [Testing & Verification](#testing--verification)
7. [Production Deployment](#production-deployment)
8. [Troubleshooting](#troubleshooting)

---

## Firebase Project Setup

### Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **"Create project"** or **"Add project"**
3. Enter project name: `bio_pass` (or your preferred name)
4. Choose your location (preferably close to your users)
5. Click **"Create project"** and wait for completion

### Step 2: Enable Firebase Services

Once your project is created, go to **Project Settings**:

#### 2.1 Authentication Setup
1. In left sidebar, go to **Build** → **Authentication**
2. Click **"Get started"**
3. Select **"Email/Password"** provider
4. Toggle **"Enable"** (should be on)
5. Leave **Email enumeration protection** as recommended
6. Click **"Save"**

#### 2.2 Firestore Database Setup
1. In left sidebar, go to **Build** → **Firestore Database**
2. Click **"Create database"**
3. Choose location (same as project)
4. Start in **"Production mode"** (we'll add security rules)
5. Click **"Create"**

#### 2.3 Cloud Functions Setup
1. In left sidebar, go to **Build** → **Functions**
2. Click **"Get started"**
3. Follow the prompts (already set up after first function deployment)

#### 2.4 Get Firebase Credentials
1. Go to **Project Settings** (gear icon, top-right)
2. Click **"Service accounts"** tab
3. Click **"Generate new private key"**
   - A JSON file will download (keep this secure, don't commit to git!)
   - Save as `firebase_credentials.json`

4. Click **"Web Apps"** section
5. Click the web app or create one if doesn't exist
6. Click the copy icon next to the Firebase config
7. Save this configuration (you'll need it for the Flutter app)

---

## Email Service Configuration

### ✅ Production-Ready Email Sending

This section configures **real email sending** for all valid email addresses during signup and authentication. The system will send OTP codes to any valid email address entered by users.

### Choose Your Email Service

You have two options:

### Option A: Gmail (Recommended for Initial Setup)

Use Gmail to quickly test and deploy OTP emails. Works for any valid email address, not just your Gmail account.

#### Step 1: Enable 2-Factor Authentication
1. Go to your Google Account: [myaccount.google.com](https://myaccount.google.com)
2. Click **"Security"** in left sidebar
3. Scroll to **"2-Step Verification"**
4. Enable it (follow Google's prompts)

#### Step 2: Generate App-Specific Password
1. Go to [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
2. Select:
   - **App**: Mail
   - **Device**: Windows PC (or your device)
3. Click **"Generate"**
4. Google will show a 16-character password
5. **Copy this password** (you'll use it in Cloud Functions)

#### Step 3: Configure in Cloud Functions
In `firebase_cloud_functions/functions/.env.local`:
```
GMAIL_USER=your_email@gmail.com
GMAIL_PASSWORD=your_app_specific_password_16_chars
```

### Option B: SendGrid (Recommended for Production Scale)

Use SendGrid for enterprise-grade email delivery. Includes better deliverability, templates, and analytics. Works for unlimited email addresses.

#### Step 1: Create SendGrid Account
1. Go to [sendgrid.com](https://sendgrid.com)
2. Sign up for free account (25,000 emails/month free)
3. Verify your account via email

#### Step 2: Generate API Key
1. In SendGrid dashboard, go to **Settings** → **API Keys**
2. Click **"Create API Key"**
3. Name it: `bio_pass_otp_service`
4. Select **"Restricted Access"**
5. Under **Mail Send**, enable:
   - Mail Send
   - Template Engine
6. Click **"Create & Verify"**
7. **Copy the API key** (you'll see it once, don't lose it!)

#### Step 3: Verify Sender Domain
1. In SendGrid, go to **Settings** → **Sender Authentication**
2. Click **"Authenticate Your Domain"**
3. Follow SendGrid's DNS verification process
4. This ensures emails come from your domain

#### Step 4: Create Email Template (Optional but Recommended)
1. In SendGrid, go to **Dynamic Templates**
2. Create new template for OTP emails
3. Get the **Template ID**
4. Update Cloud Function code to use template

#### Step 5: Configure in Cloud Functions
In `firebase_cloud_functions/functions/.env.local`:
```
SENDGRID_API_KEY=your_sendgrid_api_key
SENDGRID_FROM_EMAIL=noreply@yourdomain.com
```

---

## Firestore Database Setup

### Step 1: Create Collections & Security Rules

#### 1.1 Create Collections
Navigate to **Firestore Database** → **Collections**:

**Collection 1: `users`**
- Click **"Start Collection"**
- Collection ID: `users`
- First document ID: auto-generate
- Add fields:
  ```
  email: (string)
  password_hash: (string)
  full_name: (string)
  created_at: (timestamp)
  updated_at: (timestamp)
  is_verified: (boolean)
  phone: (string)
  bio: (string)
  ```

**Collection 2: `otp_verification`**
- Click **"Start Collection"**
- Collection ID: `otp_verification`
- Document ID: use email as document ID
- Add fields:
  ```
  email: (string)
  otp: (string)
  userID: (string)
  createdAt: (timestamp)
  expiresAt: (timestamp)
  verified: (boolean)
  attempts: (number)
  lastAttemptTime: (timestamp)
  ```

#### 1.2 Set Security Rules
1. Go to **Firestore Database** → **Rules** tab
2. Replace all content with:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Users collection - authenticated users can only read/write their own
    match /users/{userId} {
      allow read: if request.auth.uid == userId;
      allow create: if request.auth.uid == userId && 
                       request.resource.data.is_verified == false &&
                       request.resource.data.email != null;
      allow update: if request.auth.uid == userId;
      allow delete: if false; // Prevent deletion
    }

    // OTP Verification - only authenticated users can create/read/update their OTP
    match /otp_verification/{email} {
      allow create, read, update: if request.auth != null &&
                                     request.resource.data.email == request.auth.token.email;
      allow delete: if false; // Prevent deletion
    }

    // Logs collection for monitoring
    match /logs/{logId} {
      allow create: if request.auth != null;
      allow read: if false; // Only admin can read
    }

    // Default deny
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

3. Click **"Publish"**

### Step 2: Set TTL (Time-to-Live) for OTP Cleanup

1. Go to **Firestore Database** → **Data**
2. Click on `otp_verification` collection
3. Go to **Settings**
4. Click **"TTL policies"**
5. Click **"Create policy"**
6. Field: `expiresAt`
7. Click **"Create"**

This automatically deletes expired OTP records after their `expiresAt` timestamp.

---

## Cloud Functions Deployment

### Step 1: Install Firebase CLI

```bash
# Windows (PowerShell as Admin)
npm install -g firebase-tools

# Verify installation
firebase --version
```

### Step 2: Configure Cloud Functions Environment

1. Navigate to Cloud Functions directory:
```bash
cd c:\bio_pass\firebase_cloud_functions\functions
```

2. Install dependencies:
```bash
npm install
```

3. Configure your email service by setting environment variables:

**Option A - Gmail Configuration:**
Create `.env.local` file:
```env
EMAIL_SERVICE=gmail
GMAIL_USER=your_email@gmail.com
GMAIL_APP_PASSWORD=your_app_specific_password_16_chars
```

**Option B - SendGrid Configuration:**
Create `.env.local` file:
```env
EMAIL_SERVICE=sendgrid
SENDGRID_API_KEY=your_sendgrid_api_key
SENDGRID_FROM_EMAIL=noreply@yourdomain.com
```

⚠️ **Important**: The `EMAIL_SERVICE` variable determines which service is used. Make sure it matches your chosen provider.

### Step 3: Test Cloud Functions Locally

```bash
# Start Firebase emulator
firebase emulators:start --only functions

# In another terminal, test the OTP function
curl -X POST http://localhost:5001/bio_pass/us-central1/sendOTPEmail \
  -H "Content-Type: application/json" \
  -d '{
    "email": "youremail@example.com",
    "otp": "123456",
    "type": "otp_verification"
  }'

# Or test configuration
curl http://localhost:5001/bio_pass/us-central1/verifyEmailConfig
```

**Expected Response** (on success):
```json
{
  "success": true,
  "message": "OTP email sent successfully",
  "recipient": "youremail@example.com",
  "timestamp": "2026-04-06T10:30:00.000Z"
}
```

### Step 4: Deploy Cloud Functions to Firebase

```bash
# Step 4a: Login to Firebase (first time only)
firebase login

# Step 4b: Select your project
firebase use --add

# Step 4c: Deploy the functions
firebase deploy --only functions

# Step 4d: Verify deployment
firebase functions:log
```

The deployment will show output like:
```
✔  Function URL (sendOTPEmail): https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/sendOTPEmail
✔  Function URL (testEmail): https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/testEmail
✔  Function URL (verifyEmailConfig): https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/verifyEmailConfig
```

**Save the `sendOTPEmail` URL** - you'll need it for the Flutter app configuration.

### Step 5: Set Cloud Functions Runtime Configuration

Firebase Cloud Functions can securely store environment variables:

**For Gmail:**
```bash
firebase functions:config:set gmail.user="your_email@gmail.com" \
  gmail.password="your_app_specific_password"
  
firebase deploy --only functions
```

**For SendGrid:**
```bash
firebase functions:config:set sendgrid.api_key="your_api_key" \
  sendgrid.from_email="noreply@yourdomain.com"
  
firebase deploy --only functions
```

✅ **Cloud Functions will now send real OTP emails to ANY valid email address entered during signup.**

---

## Flutter App Configuration

### Step 1: Get Firebase Credentials

1. Go to Firebase Console → Project Settings
2. Scroll down to **"Your apps"** section
3. Select your Android and iOS apps (or create them)
4. Download configuration files:
   - **Android**: `google-services.json`
   - **iOS**: `GoogleService-Info.plist`

### Step 2: Add Files to Flutter Project

**Android:**
1. Place `google-services.json` in: `android/app/google-services.json`

**iOS:**
1. Open Xcode: `open ios/Runner.xcworkspace`
2. Drag `GoogleService-Info.plist` into Runner folder
3. Check **"Copy items if needed"**
4. Click **"Finish"**

### Step 3: Update Cloud Function URL

Edit `lib/services/email_service.dart`:

```dart
// Around line 11, replace with your deployed URL
static const String cloudFunctionUrl = 
    'https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/sendOTPEmail';

// Also update test email URL (around line 13)
static const String testEmailUrl = 
    'https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/testEmail';
```

Replace `YOUR_PROJECT_ID` with your actual Firebase Project ID.

### Step 4: Update Firebase Options

Edit `lib/firebase_options.dart`:

Replace the configuration with your Firebase Web App credentials from Firebase Console.

### Step 5: Configure Flutter App for Real Email Sending

Edit `lib/services/email_service.dart`:

```dart
// Set to false to enable REAL EMAIL SENDING for all valid email addresses
// Set to true ONLY if you want OTP to print to console instead (development only)
static const bool isDevelopmentMode = false;
```

**Modes:**
- `isDevelopmentMode = true`: OTP prints to VS Code Debug Console (no email sent)
- `isDevelopmentMode = false`: **Real emails sent to signup email address** ✅ (production mode)

---

## Testing & Verification

### ✅ Test Email Configuration (Before Production)

#### Quick Configuration Test

```bash
# Test that email service is properly configured
curl https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/verifyEmailConfig

# Expected response:
# {
#   "success": true,
#   "message": "Email configuration is valid and ready to use",
#   "emailService": "gmail",
#   "emailUser": "your_email@gmail.com"
# }
```

#### Send Test Email

```bash
# Send a test email to verify the service works
curl -X POST https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/testEmail \
  -H "Content-Type: application/json" \
  -d '{"email": "your_email@example.com"}'

# Check your inbox for the test email
```

### Step 1: Development Testing (OTP prints to console)

1. Set `isDevelopmentMode = true` in `lib/services/email_service.dart`
2. Run Flutter app: `flutter run`
3. Sign up with **ANY valid email** (doesn't need to be real)
4. **OTP will print to VS Code Debug Console** (not sent via email)
5. Copy OTP and enter it in the verification screen
6. Verify it works

### Step 2: Production Testing (Real emails sent)

**Prerequisites:**
- Cloud Functions deployed with email credentials
- `isDevelopmentMode = false` in Flutter app
- Firebase project ID configured in Flutter app

**Test Steps:**
1. Run Flutter app: `flutter run`
2. Sign up with **your real email address**
3. **Check your email inbox** for OTP
4. Copy OTP from email and enter in app
5. Should successfully verify

**For each signup with a different email:**
- That person will receive OTP in their inbox
- Each email can be unique, not limited to testing emails

### Step 3: Monitor Cloud Function Logs

```bash
# View real-time logs for debugging
firebase functions:log --follow

# Or via Firebase Console:
# Build → Functions → Logs tab
```

**Watch for:**
- ✅ `✅ OTP email sent to: user@example.com` (success)
- ❌ `❌ Failed to send email` (check credentials)
- ⚠️ `❌ Invalid email format` (email validation error)

---

## Production Deployment

### Pre-Deployment Checklist

- [ ] Firebase project created
- [ ] Authentication enabled (Email/Password)
- [ ] Firestore database created with security rules
- [ ] Cloud Functions deployed to Firebase
- [ ] Email service configured (Gmail or SendGrid with credentials)
- [ ] Cloud Functions credentials set via `firebase functions:config:set`
- [ ] `isDevelopmentMode` set to `false` in `lib/services/email_service.dart`
- [ ] Cloud Function URL configured in `lib/services/email_service.dart`
- [ ] Firebase credentials added to `lib/firebase_options.dart`
- [ ] Google Service files added (Android & iOS)
- [ ] All tests passed locally
- [ ] Version number updated in `pubspec.yaml`
- [ ] App icon and splash screen configured

### Step 1: Build Release APK (Android)

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Step 2: Build Release App Bundle (Android - for Play Store)

```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

### Step 3: Build iOS Release

```bash
flutter build ipa --release
# Output: build/ios/ipa/
```

### Step 4: Set Up App Store/Play Store

**Google Play Store:**
1. Go to [Google Play Console](https://play.google.com/console)
2. Create new app
3. Upload app bundle (`.aab` file)
4. Fill in all required information
5. Submit for review (takes 2-3 hours)

**Apple App Store:**
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Create new app
3. Upload IPA file via Xcode or Transporter
4. Fill in all required information
5. Submit for review (takes 1-2 days)

### Step 5: Monitor Post-Launch

1. Set up Firebase Performance Monitoring
2. Set up Crashlytics for error tracking
3. Monitor Cloud Function logs
4. Track user registration and OTP verification rates
5. Set up alerts for failures

---

## Troubleshooting

### Issue 1: "Email not found" error during OTP sending

**Cause**: User document doesn't exist in Firestore
**Solution**:
1. Verify user was created in Firebase Authentication
2. Verify user document exists in `users` collection
3. Check security rules allow write access

### Issue 2: OTP email not received

**Checklist:**

1. **Check Cloud Function Logs:**
```bash
firebase functions:log
```
Look for error messages indicating what went wrong.

2. **Gmail Issues:**
   - [ ] 2FA is enabled on Gmail account
   - [ ] App-specific password is correct (16 chars, spaces removed)
   - [ ] `EMAIL_SERVICE=gmail` is set
   - [ ] `GMAIL_USER` and `GMAIL_APP_PASSWORD` are configured
   - [ ] Cloud functions redeployed after credential changes

3. **SendGrid Issues:**
   - [ ] API key is valid (regenerate if needed)
   - [ ] API key has "Mail Send" permission enabled
   - [ ] `EMAIL_SERVICE=sendgrid` is set
   - [ ] `SENDGRID_API_KEY` and `SENDGRID_FROM_EMAIL` are configured
   - [ ] Domain verification is complete (if using custom domain)
   - [ ] Cloud functions redeployed after credential changes

4. **General Issues:**
   - [ ] Cloud Functions deployed: `firebase deploy --only functions`
   - [ ] Correct Cloud Function URL in Flutter app
   - [ ] Email address is valid format (xxx@example.com)
   - [ ] Check spam/junk folder in email inbox
   - [ ] Verify email configuration: `curl https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/verifyEmailConfig`

5. **Email going to spam (Production):**
   - Use SendGrid for better deliverability
   - Verify sender domain
   - Add SPF and DKIM records
   - Test emails with SendGrid's email validation

### Issue 3: "Cloud function request timeout"

**This means the Cloud Function took too long to respond.**

**Solutions:**
1. Check Cloud Function logs:
```bash
firebase functions:log
```

2. Verify email credentials are correct (wrong credentials cause delays)

3. Increase timeout in `lib/services/email_service.dart`:
```dart
const int emailTimeout = 30; // increase from 30 to 60 seconds
```

4. Test email configuration:
```bash
curl https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/verifyEmailConfig
```

### Issue 4: Security rules blocking access

**Check**:
1. User is authenticated in Firebase Auth
2. Document structure matches security rules
3. Email field exists and matches
4. User ID matches auth UID

### Issue 5: OTP not printing to console (Development Mode)

**Solution**:
1. Ensure `isDevelopmentMode = true` in `lib/services/email_service.dart`
2. Check **VS Code Debug Console** (not Terminal) - this is important!
3. Run app with `flutter run` (not through Android Studio)
4. Look for the purple box with separators

**Example Console Output:**
```
═════════════════════════════════════════════
DEVELOPMENT MODE - OTP for Testing
═════════════════════════════════════════════
Email: user@example.com
OTP Code: 123456
Valid for: 10 minutes
═════════════════════════════════════════════
```

### Issue 6: Firestore quota exceeded

**Solutions**:
1. Implement index optimization
2. Batch write operations
3. Implement caching layer
4. Upgrade Firebase plan

---

## Security Best Practices

### 1. Protect Sensitive Data

```dart
// NEVER commit these to git:
- google-services.json
- GoogleService-Info.plist
- .env.local with credentials
- firebase_credentials.json

// Add to .gitignore:
android/app/google-services.json
ios/**/GoogleService-Info.plist
firebase_cloud_functions/functions/.env.local
firebase_credentials.json
```

### 2. Use Environment Variables

```bash
# Never hardcode credentials, use environment variables
firebase functions:config:set gmail.user="$GMAIL_USER" gmail.password="$GMAIL_PASSWORD"
```

### 3. Implement Rate Limiting

The OTP service includes:
- 5-attempt maximum per OTP
- 60-second cooldown between resends
- 10-minute OTP expiry

### 4. Use HTTPS for All Communications

- All Cloud Functions are HTTPS by default
- All Firebase services are encrypted
- Enable SSL pinning for production

### 5. Monitor and Alert

```bash
# Set up email alerts for function errors
firebase functions:config:set alerts.email="admin@yourdomain.com"
```

---

## Support & Resources

- [Firebase Documentation](https://firebase.google.com/docs)
- [Cloud Functions Guide](https://firebase.google.com/docs/functions)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/start)
- [Gmail App Passwords](https://support.google.com/accounts/answer/185833)
- [SendGrid API Reference](https://docs.sendgrid.com/api-reference)
- [Flutter Firebase Plugins](https://pub.dev/packages/firebase_core)

---

## Quick Reference Commands

```bash
# Firebase CLI
firebase login                          # Login to Firebase
firebase use --add                      # Select project
firebase deploy                         # Deploy everything
firebase deploy --only functions        # Deploy functions only
firebase functions:log                  # View function logs
firebase functions:config:set KEY VALUE # Set config

# Flutter
flutter pub get                         # Get dependencies
flutter run -d emulator-5554           # Run on emulator
flutter build apk --release            # Build Android APK
flutter build ipa --release            # Build iOS app

# NPM (for Cloud Functions)
npm install                             # Install dependencies
npm test                                # Run tests
npm start                               # Start local emulator
```

---

**Last Updated**: April 2026
**Version**: 1.0
**Status**: Production Ready
