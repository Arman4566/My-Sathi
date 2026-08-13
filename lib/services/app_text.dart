/// A lightweight translation helper — not a full flutter_localizations
/// setup, but enough to demonstrate language switching. Add more keys
/// as you translate more of the app; anything missing falls back to
/// English automatically.
class AppText {
  static const Map<String, Map<String, String>> _strings = {
    'en': {
      'good_day': 'Good day',
      'health_summary': "Here's your health summary for today",
      'todays_medicines': "Today's medicines",
      'no_medicines': 'No medicines yet. Scan a prescription to get started.',
      'my_medicines': 'My medicines',
      'appointments': 'Appointments',
      'ask_assistant': 'Ask assistant',
      'scan_prescription': 'Scan prescription',
      'reports': 'Reports',
      'my_health': 'My health',
      'profile': 'Profile',
      'settings': 'Settings',
      'dark_mode': 'Dark mode',
      'language': 'Language',
      'logout': 'Log out',
      'login': 'Log in',
      'signup': 'Sign up',
      'email': 'Email',
      'password': 'Password',
      'name': 'Name',
      // Chatbot
      'health_assistant': 'Health Assistant',
      'chat_greeting_default':
          "Hi! I'm your health assistant. I know your current medicines, "
              "appointments, and reports, so feel free to ask me about your "
              "own situation — or ask me to add a medicine or appointment "
              "and I'll confirm the details with you before saving anything.",
      'chat_greeting_context':
          "Hi! I can see you'd like to discuss: {context}. "
              "Ask me anything about it — I'll explain in plain language. "
              "For anything specific to your treatment, I'll always suggest "
              "checking with your doctor or pharmacist too.",
      'listening': 'Listening…',
      'voice_input': 'Voice input',
      'voice_input_unavailable': 'Voice input unavailable on this device',
      'chat_hint': 'e.g. "I missed my evening dose"',
      'added_confirmation': '✅ Added.',
      'add_medicine_q': 'Add medicine?',
      'add_appointment_q': 'Add appointment?',
      'not_now': 'Not now',
      'confirm': 'Confirm',
      // Home screen leftovers
      'upcoming_appointment': 'Upcoming appointment',
      'prescriptions': 'Prescriptions',
      // Settings screen
      'reminder_alarm_sound': 'Reminder alarm sound',
      'sound_on_desc':
          'Reminders ring like an alarm, even if your phone is on silent',
      'sound_off_desc':
          "Reminders arrive as a normal notification only, and respect "
              "your phone's silent/vibrate mode",
      // Medicine list screen
      'delete_medicine_q': 'Delete medicine?',
      'delete_medicine_body':
          'This permanently removes "{name}" and its reminders. This cannot be undone.',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'add_medicine': 'Add medicine',
      'edit_medicine': 'Edit medicine',
      'medicine_name': 'Medicine name',
      'dosage_hint': 'Dosage (e.g. 500mg)',
      'instructions_hint': 'Instructions (e.g. after food)',
      'reminder_times': 'Reminder times',
      'add_time': 'Add time',
      'frequency': 'Frequency',
      'every_day': 'Every day',
      'custom_days': 'Custom days',
      'stop_after_optional': 'Stop after (optional)',
      'no_end_date': 'No end date — ongoing',
      'end_date_note':
          'When an end date passes, this medicine is automatically '
              'stopped and its reminders removed.',
      'save': 'Save',
      'could_not_save': 'Could not save: {error}',
      'saved_reminders_failed':
          'Saved, but reminders could not be scheduled. '
              'Check notification/alarm permissions in phone settings.',
      'no_active_medicines': 'No active medicines',
      'edit': 'Edit',
      'stop_keep_history': 'Stop (keep in history)',
      'delete_permanently': 'Delete permanently',
      'on_days': 'On {days}',
      'until_date': ' • until {date}',
      // Appointments screen
      'new_appointment': 'New appointment',
      'edit_appointment': 'Edit appointment',
      'doctors_name': "Doctor's name",
      'location': 'Location',
      'pick_date': 'Pick date',
      'pick_time': 'Pick time',
      'saved_reminder_failed':
          'Saved, but the reminder could not be scheduled. '
              'Check notification/alarm permissions in phone settings.',
      'delete_appointment_q': 'Delete appointment?',
      'delete_appointment_body':
          'This will remove Dr. {doctor} on {date} and cancel its reminder.',
      'no_upcoming_appointments': 'No upcoming appointments',
      // Profile screen
      'not_logged_in': 'Not logged in',
      'edit_field': 'Edit {field}',
      'age': 'Age',
      'weight_kg': 'Weight (kg)',
      'height_cm': 'Height (cm)',
      'gender': 'Gender',
      'not_set': 'Not set',
      'bmi_label': 'BMI: {value}',
      'female': 'Female',
      'male': 'Male',
      'other': 'Other',
      // Health screen
      'log_current_health': 'Log current health',
      'weight_kg_hint': 'Weight (kg)',
      'blood_pressure_hint': 'Blood pressure (e.g. 120/80)',
      'blood_sugar_hint': 'Blood sugar (mg/dL)',
      'feeling_notes_hint': 'How are you feeling? (notes)',
      'no_health_records': 'No health records yet.\nTap + to log how you feel today.',
      'health_note': 'Health note',
      'bp_label': 'BP {value}',
      'sugar_label': 'Sugar {value} mg/dL',
      // Reports screen
      'my_reports': 'My reports',
      'no_reports': 'No reports uploaded yet.\nTap + to add a lab report or document.',
      'summarized_suffix': ' • summarized',
      // Scan prescription screen
      'edit_medicine_title': 'Edit medicine',
      'medicine_name_short': 'Medicine name',
      'dosage_short': 'Dosage',
      'instructions_short': 'Instructions',
      'done': 'Done',
      'could_not_open_camera_gallery':
          'Could not open the {source}. Check that this app has camera/photo '
              'permission in your phone settings, then try again.',
      'camera': 'camera',
      'gallery': 'gallery',
      'no_medicines_detected':
          'No medicines could be detected in this photo. You can add them '
              'manually from the "My medicines" screen instead.',
      'could_not_read_prescription':
          'Could not read this prescription automatically. You can still '
              'add medicines manually from the "My medicines" screen.',
      'nothing_saved_missing_fields':
          'Nothing was saved — the detected item(s) were missing a name or '
              'a reminder time. Tap edit on each item to fill those in before saving.',
      'items_skipped':
          '{count} item(s) were skipped (missing name or reminder time) — '
              'the rest were saved.',
      'reminders_failed_count':
          'Saved, but {count} reminder(s) could not be scheduled. '
              'Check notification/alarm permissions in phone settings.',
      'take_photo': 'Take photo',
      'from_gallery': 'From gallery',
      'review_before_saving': 'Please review before saving',
      'automatic_reading_note':
          "Automatic reading isn't perfect — tap any item to fix the name, "
              "dose, times, frequency, or add an end date.",
      'custom_pick_days': 'Custom (pick days)',
      'name_unclear': '(name unclear)',
      'confirm_and_save': 'Confirm & save',
      // Auth screens (login/signup/forgot password/splash)
      'welcome_back': 'Welcome back',
      'forgot_password_q': 'Forgot password?',
      'log_in': 'Log in',
      'no_account_signup': "Don't have an account? Sign up",
      'create_account': 'Create account',
      'confirm_password': 'Confirm password',
      'passwords_dont_match': 'Passwords don\'t match',
      'sign_up': 'Sign up',
      'have_account_login': 'Already have an account? Log in',
      'reset_password': 'Reset password',
      'reset_password_note':
          "Enter your account email and we'll send you a link to reset your password.",
      'send_reset_link': 'Send reset link',
      'reset_link_sent': 'Check your email for a password reset link.',
      'back_to_login': 'Back to login',
      'please_fill_fields':
          'Please fill in all fields (password: at least 4 characters).',
      'account_saved_note':
          'Your account is saved securely to your account server, so you '
              'can log in from another device and recover your password if '
              'you forget it.',
      'code_sent_info':
          'If that email is registered, a 6-digit code has been sent. '
              'It expires in 15 minutes.',
      'enter_code_password': 'Enter the code and a password of at least 4 characters.',
      'password_updated_login': 'Password updated. Please log in.',
      'enter_email_reset_note':
          "Enter your account email and we'll send you a 6-digit reset code.",
      'send_reset_code': 'Send reset code',
      'six_digit_code': '6-digit code',
      'new_password': 'New password',
      'use_different_email': 'Use a different email',
      'health_companion_tagline': 'Your health companion',
      // Prescription history / detail
      'reports_and_prescriptions': 'Reports & prescriptions',
      'no_scanned_yet': 'No scanned prescriptions or reports yet.',
      'scanned_document': 'Scanned document',
      'report_details': 'Report details',
      'delete_report_q': 'Delete this report?',
      'delete_report_body':
          "This removes it from your records. It won't affect any medicine reminders already saved.",
      'scanned_on': 'Scanned on {date}',
      'extracted_text': 'Extracted text',
      'no_text_detected': '(no text detected)',
      'discuss_with_assistant': 'Discuss this report with the assistant',
      'scanned_report_from': 'Scanned report from {date}',
      'uploaded_on': 'Uploaded {date}',
      'ai_summary': 'AI summary',
      // Report upload screen
      'summary_unavailable':
          "Couldn't generate an AI summary right now (backend may not be "
              "reachable), but the report itself has been read and can still be saved.",
      'could_not_read_photo_text': 'Could not read text from this photo.',
      'report_dated_title': 'Report — {date}',
      'upload_report': 'Upload report',
      'title_hint': 'Title (e.g. "Blood test — June")',
      'summary_disclaimer':
          'This is a plain-language summary, not a diagnosis. Discuss anything '
              'flagged as unusual with your doctor.',
      'save_report': 'Save report',
      // Alarm ring screen
      'snooze_5min': 'Snooze 5 min',
      'dismiss': 'Dismiss',
      'time_for_medicine': 'Time to take your medicine 💊',
      'time_for_medicine_doctor': 'Time to take your medicine 💊 (Dr. {doctor})',
      'upcoming_appointment_title': 'Upcoming appointment 🗓️',
      'appointment_body': 'Dr. {doctor} at {time} — {location}',
    },
    'hi': {
      'good_day': 'नमस्ते',
      'health_summary': 'आज का आपका स्वास्थ्य सारांश यहाँ है',
      'todays_medicines': 'आज की दवाइयाँ',
      'no_medicines': 'अभी कोई दवा नहीं है। शुरू करने के लिए पर्ची स्कैन करें।',
      'my_medicines': 'मेरी दवाइयाँ',
      'appointments': 'अपॉइंटमेंट',
      'ask_assistant': 'सहायक से पूछें',
      'scan_prescription': 'पर्ची स्कैन करें',
      'reports': 'रिपोर्ट',
      'my_health': 'मेरा स्वास्थ्य',
      'profile': 'प्रोफ़ाइल',
      'settings': 'सेटिंग्स',
      'dark_mode': 'डार्क मोड',
      'language': 'भाषा',
      'logout': 'लॉग आउट',
      'login': 'लॉग इन करें',
      'signup': 'साइन अप करें',
      'email': 'ईमेल',
      'password': 'पासवर्ड',
      'name': 'नाम',
      // Chatbot
      'health_assistant': 'स्वास्थ्य सहायक',
      'chat_greeting_default':
          "नमस्ते! मैं आपका स्वास्थ्य सहायक हूँ। मुझे आपकी मौजूदा दवाइयाँ, "
              "अपॉइंटमेंट और रिपोर्ट्स की जानकारी है, तो आप मुझसे अपनी स्थिति के "
              "बारे में कुछ भी पूछ सकते हैं — या मुझसे कोई दवा या अपॉइंटमेंट जोड़ने "
              "को कह सकते हैं, मैं सेव करने से पहले आपसे विवरण की पुष्टि करूँगा।",
      'chat_greeting_context':
          "नमस्ते! मुझे पता है आप इस बारे में बात करना चाहते हैं: {context}। "
              "इसके बारे में कुछ भी पूछें — मैं आसान भाषा में समझाऊँगा। आपके इलाज से "
              "जुड़ी किसी भी खास बात के लिए, मैं हमेशा आपके डॉक्टर या फार्मासिस्ट से "
              "सलाह लेने की सलाह दूँगा।",
      'listening': 'सुन रहा हूँ…',
      'voice_input': 'आवाज़ से इनपुट',
      'voice_input_unavailable': 'इस फ़ोन पर आवाज़ इनपुट उपलब्ध नहीं है',
      'chat_hint': 'जैसे "मैं अपनी शाम की दवा भूल गया"',
      'added_confirmation': '✅ जोड़ दिया गया।',
      'add_medicine_q': 'दवा जोड़ें?',
      'add_appointment_q': 'अपॉइंटमेंट जोड़ें?',
      'not_now': 'अभी नहीं',
      'confirm': 'पुष्टि करें',
      // Home screen leftovers
      'upcoming_appointment': 'आगामी अपॉइंटमेंट',
      'prescriptions': 'पर्चियाँ',
      // Settings screen
      'reminder_alarm_sound': 'रिमाइंडर अलार्म ध्वनि',
      'sound_on_desc':
          'फ़ोन साइलेंट होने पर भी रिमाइंडर अलार्म की तरह बजेगा',
      'sound_off_desc':
          'रिमाइंडर सिर्फ़ एक सामान्य सूचना के रूप में आएगा, और आपके फ़ोन के '
              'साइलेंट/वाइब्रेट मोड का सम्मान करेगा',
      // Medicine list screen
      'delete_medicine_q': 'दवा हटाएँ?',
      'delete_medicine_body':
          '"{name}" और उसके रिमाइंडर हमेशा के लिए हट जाएँगे। इसे वापस नहीं किया जा सकता।',
      'cancel': 'रद्द करें',
      'delete': 'हटाएँ',
      'add_medicine': 'दवा जोड़ें',
      'edit_medicine': 'दवा संपादित करें',
      'medicine_name': 'दवा का नाम',
      'dosage_hint': 'खुराक (जैसे 500mg)',
      'instructions_hint': 'निर्देश (जैसे खाने के बाद)',
      'reminder_times': 'रिमाइंडर समय',
      'add_time': 'समय जोड़ें',
      'frequency': 'आवृत्ति',
      'every_day': 'हर दिन',
      'custom_days': 'चुनिंदा दिन',
      'stop_after_optional': 'इसके बाद बंद करें (वैकल्पिक)',
      'no_end_date': 'कोई अंतिम तारीख नहीं — जारी रहेगी',
      'end_date_note':
          'अंतिम तारीख आने पर, यह दवा और इसके रिमाइंडर अपने आप बंद हो जाएँगे।',
      'save': 'सेव करें',
      'could_not_save': 'सेव नहीं हो सका: {error}',
      'saved_reminders_failed':
          'सेव हो गया, लेकिन रिमाइंडर शेड्यूल नहीं हो सके। फ़ोन सेटिंग्स में '
              'नोटिफिकेशन/अलार्म अनुमतियाँ जाँचें।',
      'no_active_medicines': 'कोई सक्रिय दवा नहीं',
      'edit': 'संपादित करें',
      'stop_keep_history': 'बंद करें (इतिहास में रखें)',
      'delete_permanently': 'हमेशा के लिए हटाएँ',
      'on_days': '{days} को',
      'until_date': ' • {date} तक',
      // Appointments screen
      'new_appointment': 'नई अपॉइंटमेंट',
      'edit_appointment': 'अपॉइंटमेंट संपादित करें',
      'doctors_name': 'डॉक्टर का नाम',
      'location': 'स्थान',
      'pick_date': 'तारीख चुनें',
      'pick_time': 'समय चुनें',
      'saved_reminder_failed':
          'सेव हो गया, लेकिन रिमाइंडर शेड्यूल नहीं हो सका। फ़ोन सेटिंग्स में '
              'नोटिफिकेशन/अलार्म अनुमतियाँ जाँचें।',
      'delete_appointment_q': 'अपॉइंटमेंट हटाएँ?',
      'delete_appointment_body':
          'इससे डॉ. {doctor} की {date} की अपॉइंटमेंट हट जाएगी और उसका रिमाइंडर रद्द हो जाएगा।',
      'no_upcoming_appointments': 'कोई आगामी अपॉइंटमेंट नहीं',
      // Profile screen
      'not_logged_in': 'लॉग इन नहीं है',
      'edit_field': '{field} संपादित करें',
      'age': 'आयु',
      'weight_kg': 'वज़न (kg)',
      'height_cm': 'ऊँचाई (cm)',
      'gender': 'लिंग',
      'not_set': 'सेट नहीं है',
      'bmi_label': 'BMI: {value}',
      'female': 'महिला',
      'male': 'पुरुष',
      'other': 'अन्य',
      // Health screen
      'log_current_health': 'वर्तमान स्वास्थ्य दर्ज करें',
      'weight_kg_hint': 'वज़न (kg)',
      'blood_pressure_hint': 'रक्तचाप (जैसे 120/80)',
      'blood_sugar_hint': 'ब्लड शुगर (mg/dL)',
      'feeling_notes_hint': 'आप कैसा महसूस कर रहे हैं? (नोट्स)',
      'no_health_records':
          'अभी कोई स्वास्थ्य रिकॉर्ड नहीं है।\nआज आप कैसा महसूस कर रहे हैं, दर्ज करने के लिए + दबाएँ।',
      'health_note': 'स्वास्थ्य नोट',
      'bp_label': 'BP {value}',
      'sugar_label': 'शुगर {value} mg/dL',
      // Reports screen
      'my_reports': 'मेरी रिपोर्ट्स',
      'no_reports': 'अभी कोई रिपोर्ट अपलोड नहीं की गई है।\nलैब रिपोर्ट या दस्तावेज़ जोड़ने के लिए + दबाएँ।',
      'summarized_suffix': ' • सारांशित',
      // Scan prescription screen
      'edit_medicine_title': 'दवा संपादित करें',
      'medicine_name_short': 'दवा का नाम',
      'dosage_short': 'खुराक',
      'instructions_short': 'निर्देश',
      'done': 'हो गया',
      'could_not_open_camera_gallery':
          '{source} नहीं खुल सका। फ़ोन सेटिंग्स में इस ऐप को कैमरा/फ़ोटो अनुमति '
              'दी गई है या नहीं जाँचें, फिर दोबारा कोशिश करें।',
      'camera': 'कैमरा',
      'gallery': 'गैलरी',
      'no_medicines_detected':
          'इस फ़ोटो में कोई दवा नहीं मिली। आप उन्हें "मेरी दवाइयाँ" स्क्रीन से '
              'खुद जोड़ सकते हैं।',
      'could_not_read_prescription':
          'यह पर्ची अपने आप नहीं पढ़ी जा सकी। आप फिर भी "मेरी दवाइयाँ" स्क्रीन से '
              'दवाइयाँ खुद जोड़ सकते हैं।',
      'nothing_saved_missing_fields':
          'कुछ भी सेव नहीं हुआ — पाई गई वस्तुओं में नाम या रिमाइंडर समय गायब था। '
              'सेव करने से पहले हर वस्तु पर एडिट दबाकर उसे भरें।',
      'items_skipped':
          '{count} वस्तु(एँ) छोड़ दी गईं (नाम या रिमाइंडर समय गायब) — बाकी सेव हो गईं।',
      'reminders_failed_count':
          'सेव हो गया, लेकिन {count} रिमाइंडर शेड्यूल नहीं हो सके। फ़ोन सेटिंग्स '
              'में नोटिफिकेशन/अलार्म अनुमतियाँ जाँचें।',
      'take_photo': 'फ़ोटो लें',
      'from_gallery': 'गैलरी से चुनें',
      'review_before_saving': 'सेव करने से पहले जाँच लें',
      'automatic_reading_note':
          'स्वचालित रीडिंग पूरी तरह सही नहीं होती — नाम, खुराक, समय, आवृत्ति ठीक '
              'करने या अंतिम तारीख जोड़ने के लिए किसी भी वस्तु पर टैप करें।',
      'custom_pick_days': 'चुनिंदा (दिन चुनें)',
      'name_unclear': '(नाम स्पष्ट नहीं)',
      'confirm_and_save': 'पुष्टि करें और सेव करें',
      // Auth screens
      'welcome_back': 'वापसी पर स्वागत है',
      'forgot_password_q': 'पासवर्ड भूल गए?',
      'log_in': 'लॉग इन करें',
      'no_account_signup': 'खाता नहीं है? साइन अप करें',
      'create_account': 'खाता बनाएँ',
      'confirm_password': 'पासवर्ड की पुष्टि करें',
      'passwords_dont_match': 'पासवर्ड मेल नहीं खाते',
      'sign_up': 'साइन अप करें',
      'have_account_login': 'पहले से खाता है? लॉग इन करें',
      'reset_password': 'पासवर्ड रीसेट करें',
      'reset_password_note':
          'अपना अकाउंट ईमेल डालें, हम आपको पासवर्ड रीसेट करने का लिंक भेजेंगे।',
      'send_reset_link': 'रीसेट लिंक भेजें',
      'reset_link_sent': 'पासवर्ड रीसेट लिंक के लिए अपना ईमेल जाँचें।',
      'back_to_login': 'लॉग इन पर वापस जाएँ',
      'please_fill_fields': 'कृपया सभी फ़ील्ड भरें (पासवर्ड: कम से कम 4 अक्षर)।',
      'account_saved_note':
          'आपका खाता सुरक्षित रूप से आपके अकाउंट सर्वर पर सेव है, इसलिए आप किसी '
              'दूसरे डिवाइस से लॉग इन कर सकते हैं और पासवर्ड भूलने पर उसे रिकवर '
              'कर सकते हैं।',
      'code_sent_info':
          'यदि वह ईमेल पंजीकृत है, तो 6-अंकों का कोड भेज दिया गया है। यह 15 मिनट '
              'में समाप्त हो जाएगा।',
      'enter_code_password': 'कोड और कम से कम 4 अक्षरों का पासवर्ड दर्ज करें।',
      'password_updated_login': 'पासवर्ड अपडेट हो गया। कृपया लॉग इन करें।',
      'enter_email_reset_note':
          'अपना अकाउंट ईमेल डालें, हम आपको 6-अंकों का रीसेट कोड भेजेंगे।',
      'send_reset_code': 'रीसेट कोड भेजें',
      'six_digit_code': '6-अंकों का कोड',
      'new_password': 'नया पासवर्ड',
      'use_different_email': 'दूसरा ईमेल इस्तेमाल करें',
      'health_companion_tagline': 'आपका स्वास्थ्य साथी',
      // Prescription history / detail
      'reports_and_prescriptions': 'रिपोर्ट्स और पर्चियाँ',
      'no_scanned_yet': 'अभी तक कोई स्कैन की गई पर्ची या रिपोर्ट नहीं है।',
      'scanned_document': 'स्कैन किया गया दस्तावेज़',
      'report_details': 'रिपोर्ट का विवरण',
      'delete_report_q': 'यह रिपोर्ट हटाएँ?',
      'delete_report_body':
          'यह आपके रिकॉर्ड से हट जाएगी। इससे पहले से सेव किए गए किसी भी दवा '
              'रिमाइंडर पर असर नहीं पड़ेगा।',
      'scanned_on': '{date} को स्कैन किया गया',
      'extracted_text': 'निकाला गया टेक्स्ट',
      'no_text_detected': '(कोई टेक्स्ट नहीं मिला)',
      'discuss_with_assistant': 'सहायक से इस रिपोर्ट पर चर्चा करें',
      'scanned_report_from': '{date} की स्कैन की गई रिपोर्ट',
      'uploaded_on': '{date} को अपलोड की गई',
      'ai_summary': 'AI सारांश',
      // Report upload screen
      'summary_unavailable':
          'अभी AI सारांश नहीं बन सका (बैकएंड उपलब्ध नहीं हो सकता), लेकिन रिपोर्ट '
              'पढ़ ली गई है और फिर भी सेव की जा सकती है।',
      'could_not_read_photo_text': 'इस फ़ोटो से टेक्स्ट नहीं पढ़ा जा सका।',
      'report_dated_title': 'रिपोर्ट — {date}',
      'upload_report': 'रिपोर्ट अपलोड करें',
      'title_hint': 'शीर्षक (जैसे "ब्लड टेस्ट — जून")',
      'summary_disclaimer':
          'यह आसान भाषा में सारांश है, निदान नहीं। असामान्य बताई गई किसी भी बात '
              'पर अपने डॉक्टर से चर्चा करें।',
      'save_report': 'रिपोर्ट सेव करें',
      // Alarm ring screen
      'snooze_5min': '5 मिनट टालें',
      'dismiss': 'बंद करें',
      'time_for_medicine': 'आपकी दवा लेने का समय हो गया 💊',
      'time_for_medicine_doctor': 'आपकी दवा लेने का समय हो गया 💊 (डॉ. {doctor})',
      'upcoming_appointment_title': 'आगामी अपॉइंटमेंट 🗓️',
      'appointment_body': 'डॉ. {doctor}, {time} बजे — {location}',
    },
  };

  static String t(String key, String languageCode) {
    return _strings[languageCode]?[key] ?? _strings['en']![key] ?? key;
  }
}
