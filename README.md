# Sathi — Patient Care App

A patient companion app: scan prescriptions and reports with your camera,
auto-detect medicines with OCR + AI, get alarm-style medicine and
appointment reminders, track your health over time, chat with a
safety-first AI assistant (with voice input), and a real cloud account
system with password recovery.

---

## 📋 HackIndia submission — start here

### The problem
Patients managing multiple medicines — especially the elderly, those
handling chronic conditions, and people in smaller towns without easy
day-to-day access to a doctor — struggle with three connected problems no
single existing app solves together: **forgetting or mistiming doses**,
**fragmented paper/photo health records with no plain-language summary**,
and **no safe, immediate place to ask a medication question** without
guessing or waiting days for an appointment.

### Our solution
Sathi unifies all three: scan a prescription or lab report and get
AI-structured medicines and a plain-language summary (always shown for
human confirmation before saving — never auto-trusted); alarm-style
reminders that adapt to daily or custom schedules and auto-expire when a
course ends; and a safety-first AI assistant that knows your actual
medicines, appointments, and reports, can answer real questions about
your situation, and can propose adding a medicine or appointment through
conversation — but never saves anything without your explicit
confirmation. All backed by a real cloud account so your data isn't
trapped on one phone.

### Tech stack
- **Frontend**: Flutter (Android), Provider for state management
- **Local storage**: SQLite (`sqflite`) — offline-first, syncs to cloud in the background
- **Backend**: Node.js + Express, deployed on Render
- **Cloud database**: PostgreSQL (Neon/Supabase)
- **AI**: Google Gemini (`gemini-3.5-flash`, with automatic retry + model fallback on overload)
- **OCR**: Google ML Kit Text Recognition (on-device)
- **Auth**: JWT + bcrypt, with email-based password reset
- **Notifications**: `flutter_local_notifications` with exact-alarm scheduling
- **Voice input**: `speech_to_text`

### Demo video
📺 **[Add your demo video link here before submitting]**

### Screenshots
**[Add 2-3 screenshots here — good candidates: home dashboard, scan-and-confirm flow, chatbot proposing an action, a medicine reminder firing]**

### Try it yourself
This is a full-stack app (Flutter + Node backend + Postgres + Gemini), so
a live judge build requires the setup steps below — budget time for that,
or rely on the demo video for a faster look. If you've deployed the
backend already, judges only need to install the APK and log in with a
test account — see `flutter build apk --release` in the setup section
below, and consider having a pre-populated test account ready (a few
medicines, an appointment, a scanned report already added) so the app
isn't empty on first open.

### Key features checklist (what to look for in the demo)
- [ ] Scan a prescription → AI extracts medicines → user confirms before saving
- [ ] Medicine reminder fires as an alarm-style notification at the scheduled time
- [ ] Upload a lab report → AI generates a plain-language summary
- [ ] Chatbot answers a question using the patient's real medicines/appointments/reports
- [ ] Chatbot proposes adding a medicine/appointment → user must confirm before it saves
- [ ] Login on a second device pulls the same data down (cloud sync)
- [ ] Forgot-password flow sends a real reset code by email
- [ ] Dark mode and language switch apply across the whole app

---

## What's included

```
patient_care_app/
├── lib/
│   ├── models/            Medicine, Prescription, Appointment, UserProfile,
│   │                      HealthRecord, MedicalReport
│   ├── services/
│   │   ├── database_service.dart      SQLite (medicines, appointments, reports, health log)
│   │   ├── notification_service.dart  Alarm-style reminders (see below)
│   │   ├── ocr_service.dart           On-device text scan (ML Kit) + local fallback parser
│   │   ├── ai_backend_service.dart    Talks to YOUR backend (Gemini) for AI features
│   │   ├── auth_service.dart          Cloud signup/login/forgot-password
│   │   ├── settings_service.dart      Dark mode + language, persisted, app-wide
│   │   └── app_text.dart              EN/HI translation helper
│   ├── screens/            Splash, Login, Signup, ForgotPassword, Home, Scan,
│   │                       Medicines, Appointments, Reports, ReportUpload,
│   │                       ReportDetail, Health, Chatbot (voice input), Profile,
│   │                       Settings
│   └── main.dart
├── backend/
│   ├── server.js           Express app: Gemini AI endpoints
│   ├── auth.js              Cloud auth: signup/login/forgot-password/reset-password
│   ├── medicines.js         Worked example: cloud-synced medicines CRUD
│   ├── db.js                 Postgres connection pool
│   └── schema.sql            Table definitions — run this once against your DB
└── pubspec.yaml
```

## What's cloud-synced vs. what's still local — read this first

All app data now syncs to the cloud (Postgres, via the backend):
account info, medicines, appointments, scanned prescriptions/reports, and
health log entries. Logging in on a new device pulls all of it down
automatically; every add/edit/delete pushes up in the background.

**One real limitation**: photo/image fields (a medicine's photo, a
prescription/report's scanned image) are stored as **local device file
paths**, not uploaded anywhere. That path means nothing on a different
phone, so photos themselves don't follow you across devices — only the
text/data around them does (name, dosage, OCR'd text, AI summary, etc.).
Making photos available everywhere would need real cloud file storage
(e.g. Supabase Storage or S3) in addition to this database — a separate
piece of work from what's here. See the comment in `schema.sql` and
`cloud_sync_service.dart` for where to extend this if you want it.

Sync failures (offline, backend not deployed yet) never block the app —
local writes always succeed first; the cloud push happens in the
background and is simply skipped if it can't reach the backend that time.

## ⚠️ Before the chatbot or AI-powered features will work

Prescription/report scanning and the chatbot need an LLM (Google Gemini),
which lives in `backend/server.js` — never inside the app. Until deployed:
- The chatbot replies "Sorry, I couldn't reach the assistant..."
- Report summaries fail to generate
- Prescription scanning falls back to a rough on-device keyword parser

### Deploy the backend (Render.com — free tier)

1. Get a Gemini API key from **aistudio.google.com** (or Google Cloud
   Console). If you ever pasted a key into a chat, screenshot, or public
   repo, delete it there and generate a fresh one — treat any exposed key
   as compromised.
2. Set up a free Postgres database — **Neon** (neon.tech) or **Supabase**
   (supabase.com) both work well. Copy the connection string they give
   you (it looks like `postgresql://user:pass@host/db?sslmode=require`).
3. Run the schema once against that database:
   - Neon/Supabase both have a SQL editor in their dashboard — paste in
     the contents of `backend/schema.sql` and run it. (Or use `psql
     "<your connection string>" -f backend/schema.sql` from a terminal if
     you have `psql` installed.)
   - Already deployed this backend before? `schema.sql` is safe to
     re-run — it only creates tables that don't exist yet, so re-running
     it after an update just adds any new tables without touching your
     existing data.
4. Put the `backend/` folder in its own GitHub repo (or a subfolder of an
   existing one).
5. Go to render.com → New → **Web Service** → connect that repo.
   - Root directory: `backend`
   - Build command: `npm install`
   - Start command: `npm start`
6. Under **Environment**, add:
   - `GEMINI_API_KEY` = your key
   - `DATABASE_URL` = your Postgres connection string
   - `JWT_SECRET` = a long random string (generate one with
     `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`)
   - `EMAIL_USER` / `EMAIL_PASS` = optional, for forgot-password emails to
     actually send (see below) — leave blank during testing; reset codes
     will just print to Render's logs instead.
7. Deploy. Render gives you a URL like `https://sathi-backend.onrender.com`.
8. Open `lib/services/ai_backend_service.dart` and replace:
   ```dart
   static const String baseUrl = 'https://sathi-backend.onrender.com';
   ```
   (`auth_service.dart` reuses this same URL automatically.)
9. `flutter run` again.

(Free-tier Render services "sleep" after inactivity — the first request
after a while can take 20–30 seconds. Normal, not a bug.)

### Setting up the AI phone-call booking feature (optional)

The "Book by AI Phone Call" button (on the Appointments screen) has the
assistant call a doctor's office to book/confirm a slot. It's off by
default until you configure a telephony provider — without it, tapping
the button shows a clear "not set up yet" message instead of failing
silently.

1. Create a Twilio account at **twilio.com** and buy/rent a phone number
   (this is the number calls appear to come FROM).
2. **Read this before expecting it to "just work":** Twilio's free trial
   credit only lets you call phone numbers *you've manually verified* in
   the Twilio console, and it plays a "trial account" notice before your
   own message on every call. To call a real doctor's office, you need
   to upgrade to a pay-as-you-go account — there's no minimum spend, and
   voice calls run a few cents per minute, but there's no way to call an
   arbitrary number for free.
3. On Render, add three more environment variables alongside the ones
   above:
   - `TWILIO_ACCOUNT_SID` and `TWILIO_AUTH_TOKEN` — from the Twilio
     console's dashboard.
   - `TWILIO_FROM_NUMBER` — the number you bought, in `+1XXXXXXXXXX`
     format.
   - `PUBLIC_BASE_URL` — your Render URL (e.g.
     `https://sathi-backend.onrender.com`), so Twilio can call back into
     the backend while a call is live.
4. Redeploy. `schema.sql` already includes the `appointment_calls`
   table this feature uses — re-run it if you deployed the database
   before this feature was added (safe to re-run, see above).

The call script (in `backend/appointment_calls.js`) always opens by
identifying itself as an automated assistant, and never reads out the
patient's medicines, reports, or other health details to whoever
answers — only their name, the requested slot, and a callback number if
asked.

### Simulation mode (no Twilio account needed)

Every voice-calling API we checked (Twilio, Vonage, Bandwidth, Plivo,
Vapi, Bland.ai) charges per minute for real calls from the first call —
none of them are free for calling an arbitrary real phone number, and
trial credits everywhere restrict you to manually-verified numbers.
There's no way around that cost.

So if Twilio isn't set up yet (or its trial account is too restricted),
tap **"Simulate call instead"** on the Book-by-Call screen instead of
"Call to book." It runs the exact same Gemini conversation logic —
same system prompt, same rules about never sharing medical details —
but instead of a real phone ringing, you type the office's replies
yourself in a text box, and the AI responds turn by turn. Simulated
calls are clearly labeled in the UI (an amber "Simulated — no real call
was placed" badge) so they're never mistaken for a real one. This is
genuinely free and works with zero telephony setup — good for demos and
for testing the AI's conversational behavior before paying for real
calling minutes.



Without `EMAIL_USER`/`EMAIL_PASS` set, reset codes just print to your
Render logs — fine for testing, useless for real users. To send actual
emails:
- **Easiest**: use a Gmail account with an **App Password** (not your
  normal password) — see support.google.com/accounts/answer/185833.
  Set `EMAIL_USER` to that Gmail address and `EMAIL_PASS` to the app
  password.
- **More scalable**: swap the `nodemailer` Gmail transport in `auth.js`
  for a transactional email API like Resend or SendGrid — better
  deliverability at real-world volume, small code change.

## New features in this version

### Splash screen
A branded loading screen shown while the app initializes (auth check,
notification setup) — see `splash_screen.dart`.

### Book an appointment by AI phone call
On the Appointments screen, tap the phone icon in the top bar to have
the assistant call a doctor's office directly: enter the office's phone
number plus a requested date/time, and the AI places a real call
(via Twilio, see setup above), has a short back-and-forth with whoever
answers, and reports back whether the slot was confirmed. A confirmed
call can be saved straight into your appointments list. Needs the
Twilio setup above — until then it tells you clearly, rather than
pretending to call. No telephony account? Use "Simulate call instead"
on the same screen to try the identical AI conversation for free, with
you typing the office's replies (see Simulation mode above).

### Profile
WhatsApp-style layout: avatar (tap the camera badge to change it), and
tap-to-edit rows for name/age/weight/height/gender, with an
auto-calculated BMI. Saved to your cloud account.

### Reports, with AI summaries
Upload any medical document (lab report, scan, etc.) via **Reports →
Upload**. It's OCR'd on-device, then sent to your backend for a
plain-language AI summary — kept permanently, revisit anytime, and jump
straight into the chatbot to ask questions about a specific report.

### Medicine photos
Attach a photo to any medicine (packaging/strip) when adding or editing
it — shown as a thumbnail in "My medicines" and on the home dashboard.

### Alarm-style reminders
Medicine and appointment reminders now use full-screen, high-priority
alarm-style notifications (not just a quiet notification-shade ping), and
include the prescribing doctor's name when known. They repeat according
to the medicine's frequency (daily or specific weekdays) and **stop
automatically once the end date passes** — no manual cleanup needed.

One honest limitation: this uses Android's notification system with
`fullScreenIntent` + max priority, which is as close to a "ringing alarm"
as `flutter_local_notifications` gets. It's not literally the phone's
Alarm Clock app — for that exact ringing-until-dismissed UX, you'd swap
to a dedicated package like `alarm`, which is a bigger change (different
plugin, different Android permissions). Ask if you want that upgrade.

### App-wide dark mode & language
Dark mode (Settings) now applies everywhere, not just the Settings
screen — every screen reads colors from the app theme instead of
hardcoding light-mode colors. Language switching (English/Hindi) is wired
through the same pattern via `app_text.dart`; the main navigation and
several screens are translated now — extend `app_text.dart`'s maps to
cover more strings as you go (anything missing just falls back to
English, so it degrades safely).

### Reordered home screen
"Ask assistant" is now the prominent floating action button; "Scan
prescription" moved into the quick-actions grid.

### Voice input
The chatbot has a microphone button (uses `speech_to_text`) — tap to
dictate instead of typing.

### A chatbot that knows your data — and can act on it (with confirmation)
Every message now includes your current medicines, appointments, recent
report summaries, and profile as context, so you can ask things like
"what am I currently taking" or "when's my next appointment" and get a
real answer. You can also ask it to add a medicine or appointment — if
you've given enough detail (name + dose + time for a medicine; doctor +
date/time for an appointment), it proposes the exact details as a card in
the chat. **Nothing is ever saved until you tap Confirm** — same
"AI suggests, you decide" pattern used for prescription scanning
elsewhere in the app. If details are missing, it asks instead of
guessing.

## Step-by-step setup

### 1. Prerequisites
Flutter SDK 3.19+, Android Studio and/or Xcode, Node.js 18+ (backend), a
free Neon/Supabase Postgres database.

### 2. Get the Flutter app running
```bash
cd patient_care_app
flutter pub get
flutter run
```

### 3. Android setup notes
`AndroidManifest.xml` needs:
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
<!-- For "Save to gallery" in the prescription/report fullscreen viewer
     (gal package) — only needed on Android 9 (API 29) and below; gal
     uses the modern MediaStore API on Android 10+ without this. -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="29"/>
```
`RECORD_AUDIO` is for voice input in the chatbot; `USE_FULL_SCREEN_INTENT`
is for the alarm-style reminders. Also: core library desugaring must be
enabled for `flutter_local_notifications` in
`android/app/build.gradle(.kts)` (see comments there if you hit a build
error mentioning it). Minimum SDK: 21+.

**"Inconsistent JVM-target compatibility" build errors** (e.g.
`compileDebugJavaWithJavac (11) and compileDebugKotlin (1.8)`) — this
project has hit this a few times now as new plugins get added
(`flutter_local_notifications`, `flutter_timezone`, ...), because each
plugin's own Gradle module can pick a different default Java/Kotlin
target than your app module, even after you've fixed it in
`android/app/build.gradle.kts`. Instead of patching this per-plugin every
time a new one triggers it, fix it once at the **root** level: open
`android/build.gradle.kts` (not `app/build.gradle.kts`) and add this at
the end of the file:
```kotlin
subprojects {
    afterEvaluate {
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.apply {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_1_8
                targetCompatibility = JavaVersion.VERSION_1_8
            }
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
            }
        }
    }
}
```
This forces every module — your app AND every plugin — to compile
Java/Kotlin to the same target, so this class of error stops recurring
each time a new plugin is added. Run `flutter clean` after adding it.

**If you build a release APK to share with others** (`flutter build apk
--release`) and R8/ProGuard minification is enabled in your
`build.gradle(.kts)` (`isMinifyEnabled = true`), add an
`android/app/proguard-rules.pro` with at least:
```proguard
-keep class io.flutter.plugins.sqflite.** { *; }
-keep class com.dexterous.** { *; }
-keep class com.baseflow.** { *; }
```
Code shrinking can strip classes that `sqflite`, `flutter_local_notifications`,
and `speech_to_text` reach via reflection, which is one of the most common
causes of "runs fine via `flutter run` on my phone, but the shared APK
installs and then won't open on someone else's phone."

**If a shared/installed release build still won't open elsewhere**, the
single most useful thing to do is get the actual crash log rather than
guess further: connect that phone via USB (enable USB debugging), then
run `flutter run --release` targeting it from your dev machine — the
terminal will show the real exception and stack trace.

### 4. iOS setup notes
`Info.plist` needs `NSCameraUsageDescription`,
`NSPhotoLibraryUsageDescription`, and `NSMicrophoneUsageDescription` (for
voice input) plus `NSSpeechRecognitionUsageDescription`. For "Save to
gallery" in the prescription/report fullscreen viewer (`gal` package),
also add `NSPhotoLibraryAddUsageDescription` — a short string like "Save
scanned prescriptions and reports to your photos" is shown to the user
the first time they tap Save.

### 5. Get accurate device timezones (recommended)
Add `flutter_timezone` and call `tz.setLocalLocation(...)` at startup so
reminders fire at the correct local time — see comments in
`notification_service.dart`.

### 6. Deploy the backend
See the deployment section above — needed for AI scanning, report
summaries, the chatbot, and now also login/signup/password reset.

## Feature ideas worth adding next

- **Cloud photo/file storage** (Supabase Storage/S3) so medicine photos
  and scanned prescription/report images follow you across devices too —
  the one piece full sync doesn't cover yet (see the limitation above).
- **Adherence tracking**: "Taken"/"Skipped" actions on the notification
  itself, plus a weekly adherence % for doctor visits.
- **Literal ringing alarms** via the `alarm` package, if full-screen
  notifications aren't insistent enough for your users.
- **Export reports/medicine history as PDF.**
- **Caregiver notifications** on a missed dose (needs patient consent).
- **Fuller i18n** via Flutter's `gen-l10n` instead of the hand-rolled
  `app_text.dart` map, once you're translating most of the app.

## A note on health and account data

Account info, medicines, appointments, reports, and health-log entries
now all live in your cloud Postgres database (with a local SQLite copy
for offline use). This is genuinely health data now living outside the
device — encrypt in transit and at rest (Neon/Supabase do this by
default for data at rest; the app talks to your backend over HTTPS once
deployed), and check applicable regulations (HIPAA in the US, GDPR in the
EU, etc.) before launching to real users. OCR text sent for AI
parsing/summaries and chat messages (including your medicines,
appointments, and report summaries as context) go to your backend and
from there to Google's Gemini API — review Google's API data-handling
terms if that matters for your use case.
