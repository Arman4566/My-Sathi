# Patient Care App — Flutter Starter

A patient companion app: scan prescriptions with your camera, auto-detect
medicines with OCR + AI, get daily medicine reminders, appointment alerts,
and a safety-first chatbot for quick questions.

## What's included

```
patient_care_app/
├── lib/
│   ├── models/            Medicine, Prescription, Appointment
│   ├── services/
│   │   ├── database_service.dart      SQLite storage (all on-device)
│   │   ├── notification_service.dart  Local push reminders
│   │   ├── ocr_service.dart           On-device text scan (ML Kit)
│   │   └── ai_backend_service.dart    Talks to YOUR backend for AI features
│   ├── screens/            Home, Scan, Medicine list, Appointments, Chatbot
│   └── main.dart
├── backend/
│   └── server.js           Minimal Node/Express proxy to Claude's API
└── pubspec.yaml
```

## Why there's a backend folder

Two of your features — parsing a scanned prescription into structured data,
and the chatbot — need an LLM. You should **never** put an AI provider's API
key directly inside a Flutter app: anyone can pull it out of the compiled
APK/IPA in minutes and rack up charges on your account. So the pattern here
is:

```
Flutter app → your backend (holds the API key) → Claude API
```

`backend/server.js` is a small Express server that does exactly that, and
also enforces a safety system prompt for the chatbot so it never gives
patients specific dosing instructions — see the "About the chatbot" section
below.

## Step-by-step setup

### 1. Prerequisites
- Install Flutter SDK (flutter.dev) — 3.19+ recommended
- Install Android Studio (for the Android emulator/SDK) and/or Xcode (for iOS)
- Install Node.js 18+ (only needed for the backend)

### 2. Get the Flutter app running
```bash
cd patient_care_app
flutter pub get
flutter run
```
Pick a connected device or emulator when prompted.

### 3. Android setup notes
- `flutter_local_notifications` needs a notification icon at
  `android/app/src/main/res/mipmap/ic_launcher.png` (Flutter's default
  template already has this).
- In `android/app/src/main/AndroidManifest.xml`, make sure you have:
  ```xml
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
  <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
  <uses-permission android:name="android.permission.CAMERA"/>
  ```
- Minimum SDK: set `minSdkVersion 21` (or higher) in
  `android/app/build.gradle`.

### 4. iOS setup notes
- In `ios/Runner/Info.plist` add:
  ```xml
  <key>NSCameraUsageDescription</key>
  <string>Used to scan your prescription</string>
  <key>NSPhotoLibraryUsageDescription</key>
  <string>Used to pick a prescription photo</string>
  ```

### 5. Get accurate device timezones (recommended)
`notification_service.dart` uses UTC by default via the `timezone` package.
For reminders to fire at the correct *local* time, add
`flutter_timezone` and set it once at startup:
```bash
flutter pub add flutter_timezone
```
```dart
import 'package:flutter_timezone/flutter_timezone.dart';
final String currentTz = await FlutterTimezone.getLocalTimezone();
tz.setLocalLocation(tz.getLocation(currentTz));
```
Call this right after `tz_data.initializeTimeZones()` in
`NotificationService.init()`.

### 6. Set up the backend (for OCR-parsing + chatbot)
```bash
cd backend
npm install
cp .env.example .env
# edit .env and add your Anthropic API key
npm start
```
Deploy it somewhere reachable from a phone (Render, Railway, Fly.io, a small
VPS — anything that gives you a public HTTPS URL). Then open
`lib/services/ai_backend_service.dart` and replace:
```dart
static const String _baseUrl = 'https://YOUR-BACKEND-URL.example.com';
```

### 7. Try it out
- Tap **Scan prescription** → take/pick a photo → app OCRs the text on-device,
  sends it to your backend to structure into medicines → **you review and
  confirm** before anything is saved (never auto-trust AI-read handwriting).
- Confirmed medicines get local notification reminders scheduled at their
  times, repeating daily.
- **Appointments** tab lets you add an appointment; you'll get a reminder
  an hour before by default (`leadTime` is configurable).
- **Ask assistant** opens the chatbot for questions like "I missed my
  evening medicine."

## About the chatbot — a safety note

Missed-dose advice genuinely varies by medicine, and getting it wrong can be
harmful. So this chatbot is deliberately built to:
- Give general, safe information rather than a specific instruction for a
  specific drug.
- Always suggest calling the doctor/pharmacist for anything specific.
- Immediately flag emergency symptoms and tell the user to seek urgent
  care.

You can see the exact rules in `backend/server.js` under
`CHAT_SYSTEM_PROMPT`. I'd strongly recommend keeping this behavior even as
you build the app out further — a "smart" chatbot that confidently tells
patients what to do with their medication is a liability, not a feature.

## Feature ideas worth adding next

- **Adherence tracking**: log "Taken" / "Skipped" from the notification
  itself (use notification action buttons), then show a weekly streak or
  adherence % — genuinely motivating and useful for the doctor to see.
- **Refill reminders**: track pill count, alert a few days before running out.
- **Export for doctor visits**: generate a PDF summary of medicines and
  adherence history to show at the next appointment.
- **Caregiver/family notifications**: optionally notify a family member if a
  dose is missed by more than a set window (needs the patient's consent and
  a lightweight backend to relay it).
- **Multiple patient profiles**: useful for a caregiver managing meds for a
  parent or child.
- **Interaction/duplicate warnings**: flag if a newly scanned prescription
  seems to duplicate or plausibly interact with an existing medicine —
  always frame this as "ask your pharmacist about this" rather than a
  verdict.
- **Dark mode** and **large-text/accessibility mode** — genuinely important
  for an elderly-skewing user base.

## A note on health data

All medicine, prescription, and appointment data stored by this starter
stays in a local SQLite database on the device — nothing is uploaded except
the OCR text you explicitly send to your backend for AI parsing, and chat
messages sent to the assistant. If you add cloud sync, family sharing, or
analytics later, treat this as health data: encrypt it in transit and at
rest, and check what regulations apply in your target markets (e.g. HIPAA
in the US, GDPR in the EU) before launching.
