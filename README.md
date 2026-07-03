# Patient Care App — Flutter Starter

A patient companion app: scan prescriptions with your camera, auto-detect
medicines with OCR + AI, get daily or custom-schedule medicine reminders,
appointment alerts, a reports/prescription history, a health log, a
safety-first chatbot, and local login + profile/settings.

## What's included

```
patient_care_app/
├── lib/
│   ├── models/            Medicine, Prescription, Appointment, UserProfile, HealthRecord
│   ├── services/
│   │   ├── database_service.dart      SQLite storage (all on-device)
│   │   ├── notification_service.dart  Local push reminders (daily or custom weekdays)
│   │   ├── ocr_service.dart           On-device text scan (ML Kit) + local fallback parser
│   │   ├── ai_backend_service.dart    Talks to YOUR backend for AI features
│   │   ├── auth_service.dart          Local (device-only) signup/login
│   │   ├── settings_service.dart      Dark mode + language, persisted
│   │   └── app_text.dart              Minimal EN/HI translation helper
│   ├── screens/            Login, Signup, Home, Scan, Medicines, Appointments,
│   │                       Reports history + detail, Health log, Chatbot,
│   │                       Profile, Settings
│   └── main.dart
├── backend/
│   └── server.js           Minimal Node/Express proxy to Claude's API
└── pubspec.yaml
```

## ⚠️ Before the chatbot or AI-powered scanning will work

Both the prescription-scan parser and the chatbot need an LLM, which lives
in `backend/server.js` — **not** inside the app. Until that backend is
deployed, `ai_backend_service.dart` is pointed at a placeholder URL and:
- The chatbot will always reply "Sorry, I couldn't reach the assistant..."
- Prescription scanning falls back to a rough on-device keyword parser
  (catches lines with words like TAB/CAP/SYRUP/MG) — much less accurate
  than the real AI parser, but at least gives you something to edit.

### Deploy the backend (Render.com — free tier, beginner-friendly)

1. Get an API key from console.anthropic.com.
2. Put the `backend/` folder in its own GitHub repo (or a folder in your
   existing repo).
3. Go to render.com → New → **Web Service** → connect that repo.
   - Root directory: `backend`
   - Build command: `npm install`
   - Start command: `npm start`
4. Under **Environment**, add a variable: `ANTHROPIC_API_KEY` = your key.
5. Deploy. Render gives you a public URL like
   `https://my-sathi-backend.onrender.com`.
6. Open `lib/services/ai_backend_service.dart` and replace:
   ```dart
   static const String _baseUrl = 'https://my-sathi-backend.onrender.com';
   ```
7. `flutter run` again — scanning and the chatbot should now work.

(Free-tier Render services "sleep" after inactivity, so the first request
after a while may take 20–30 seconds — that's normal, not a bug.)

## New features in this version

### Editable, schedulable medicines
- **Add/edit/delete medicines directly** from "My medicines" — no scan required.
- **Scan suggestions are now editable** — tap any detected medicine to fix
  its name, dose, times, frequency, or set an end date before saving.
- **Frequency**: every day, or custom weekdays (e.g. Mon/Wed/Fri).
- **Auto-expiry**: set an optional end date and the medicine automatically
  deactivates (and its reminders cancel) once that date passes. Checked
  every time the medicine list loads.

### Appointments
- Edit and delete appointments (not just add) — tap an appointment or use
  the edit/delete icons. Deleting also cancels its reminder.

### Reports & prescription history
- Every scan is saved permanently under **Reports** on the home screen —
  revisit the photo and extracted text anytime.
- From a report's detail view, tap **"Discuss this report with the
  assistant"** to open the chatbot with that report's text as context, so
  you can ask questions about it directly.

### My health
- A simple health log: weight, blood pressure, blood sugar, and free-text
  notes, timestamped. Good for tracking trends between doctor visits.

### Login, profile, and settings
- **Local sign-up/login** — see the important caveat below.
- **Profile**: name, age, weight, height, gender, with an auto-calculated BMI.
- **Settings**: dark mode toggle, language (English/Hindi — a small
  starting translation set, see `app_text.dart` to extend it), and logout.

## ⚠️ Important: the login system is local-only

`auth_service.dart` implements signup/login entirely on-device (SQLite +
hashed password), with no server. This is a reasonable starting point for
a personal, single-user app, but be aware:
- **No password recovery.** If forgotten, there's no "reset" flow — you'd
  need to clear app data and sign up again (losing local health data too).
- **No multi-device sync.** An account only exists on the phone it was
  created on.
- **Not suitable as-is for a real multi-user product.** For that, you'd
  move authentication to a real backend with proper password hashing
  (bcrypt/argon2), sessions/tokens, and a account-recovery flow — a
  meaningfully bigger project than what's here.

## Step-by-step setup

### 1. Prerequisites
- Flutter SDK 3.19+, Android Studio and/or Xcode, Node.js 18+ (for the backend)

### 2. Get the Flutter app running
```bash
cd patient_care_app
flutter pub get
flutter run
```

### 3. Android setup notes
- `AndroidManifest.xml` needs:
  ```xml
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
  <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
  <uses-permission android:name="android.permission.CAMERA"/>
  ```
- `android/app/build.gradle(.kts)` needs core library desugaring enabled
  for `flutter_local_notifications` — see comments in that file if you hit
  a "requires core library desugaring" build error.
- Minimum SDK: 21+.

### 4. iOS setup notes
- `Info.plist` needs `NSCameraUsageDescription` and
  `NSPhotoLibraryUsageDescription`.

### 5. Get accurate device timezones (recommended)
Add `flutter_timezone` and call `tz.setLocalLocation(...)` at startup so
reminders fire at the correct local time — see comments in
`notification_service.dart`.

### 6. Deploy the backend
See the "Before the chatbot or AI-powered scanning will work" section above.

## Feature ideas worth adding next

- **Adherence tracking**: "Taken"/"Skipped" actions on the notification
  itself, plus a weekly adherence % — great to show a doctor.
- **Refill reminders** based on pill count.
- **Export reports/medicine history as PDF** for doctor visits.
- **Caregiver notifications** if a dose is missed (needs patient consent
  and a lightweight backend to relay it).
- **Proper multi-device accounts** via a real backend, if you outgrow the
  local-login approach.
- **Fuller i18n** — `app_text.dart` currently covers a handful of strings;
  migrating to Flutter's `gen-l10n` would scale this much further.

## A note on health data

Medicine, prescription, appointment, profile, and health-log data all stay
in a local SQLite database on the device. Only OCR text sent for AI
parsing and chat messages (including report text, if you use "Discuss
this report") leave the device, and only to your own backend. If you add
cloud sync or multi-device accounts later, treat this as health data:
encrypt in transit and at rest, and check applicable regulations (HIPAA in
the US, GDPR in the EU, etc.) before launching.

