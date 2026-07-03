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
    },
  };

  static String t(String key, String languageCode) {
    return _strings[languageCode]?[key] ?? _strings['en']![key] ?? key;
  }
}
