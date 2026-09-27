import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../models/nearby_doctor.dart';
import 'ai_backend_service.dart';
import 'auth_service.dart';

/// Thrown for location problems the UI needs to explain specifically
/// (e.g. "turn on location services" vs "permission denied") rather than
/// showing a generic error.
class LocationException implements Exception {
  final String message;
  LocationException(this.message);
  @override
  String toString() => message;
}

/// "Find nearby doctors": gets the patient's current location, sends it
/// (plus either a described medical condition or a chosen specialty) to
/// the backend, and returns only doctors the backend has already filtered
/// to a minimum rating/review count. See backend/doctors.js for why the
/// specialist-matching step is a category lookup, not a diagnosis, and
/// for the actual filtering logic — this class never re-implements or
/// loosens that filtering client-side.
class DoctorFinderService {
  DoctorFinderService._internal();
  static final DoctorFinderService instance = DoctorFinderService._internal();

  String get _baseUrl => AiBackendService.baseUrl;

  /// Requests location permission if needed and returns the device's
  /// current position. Throws [LocationException] with a message safe to
  /// show directly to the patient if location can't be obtained.
  Future<Position> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationException(
          'Location services are turned off. Please enable location and try again.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationException(
            'Location permission was denied, so nearby doctors can\'t be found. '
            'Please allow location access and try again.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationException(
          'Location permission is permanently denied. Please enable it for this '
          'app in your phone\'s Settings to find nearby doctors.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    );
  }

  /// [medicalCondition] is free text the patient typed describing how
  /// they feel — the backend's AI step maps it to one specialist
  /// category. [specialty] is used instead when the patient tapped a
  /// quick-pick chip directly; pass only one of the two.
  Future<DoctorSearchResult> findNearbyDoctors({
    required double latitude,
    required double longitude,
    String? medicalCondition,
    String? specialty,
    double radiusMeters = 5000,
  }) async {
    final token = await AuthService.instance.getToken();
    if (token == null) {
      throw Exception('Please log in to search for nearby doctors.');
    }

    final res = await http.post(
      Uri.parse('$_baseUrl/api/doctors/nearby'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        if (medicalCondition != null && medicalCondition.trim().isNotEmpty)
          'medicalCondition': medicalCondition.trim(),
        if (specialty != null) 'specialty': specialty,
        'radiusMeters': radiusMeters,
      }),
    );

    if (res.statusCode != 200) {
      String message = 'Could not search for doctors right now. Please try again.';
      try {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        message = (data['message'] as String?) ?? message;
      } catch (_) {}
      throw Exception(message);
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return DoctorSearchResult.fromJson(data);
  }

  /// Opens directions to [doctor] — OpenStreetMap's own directions page
  /// when available, otherwise just the map view centered on the place.
  Future<bool> openDirections(NearbyDoctor doctor) {
    final url = (doctor.directionsUrl != null && doctor.directionsUrl!.isNotEmpty)
        ? doctor.directionsUrl!
        : doctor.mapsUrl;
    final uri = Uri.parse(url);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Opens the phone's dialer pre-filled with [doctor]'s number.
  Future<bool> call(NearbyDoctor doctor) {
    if (doctor.phone == null || doctor.phone!.isEmpty) return Future.value(false);
    final uri = Uri(scheme: 'tel', path: doctor.phone);
    return launchUrl(uri);
  }
}
