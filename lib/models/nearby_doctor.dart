/// A single doctor/clinic returned by the "Find nearby doctors" backend
/// search (see backend/doctors.js). Never persisted locally — this is
/// fetched fresh each time the patient searches, same as chat/report
/// results from ai_backend_service.dart.
///
/// Data comes from OpenStreetMap, which has no built-in rating/review
/// system — that's why there's no `rating`/`reviewCount` here. Results
/// are ranked by [distanceMeters] instead.
class NearbyDoctor {
  final String placeId;
  final String name;
  final String specialty;
  final String address;
  final bool? isOpenNow;
  final int? distanceMeters;
  final double? latitude;
  final double? longitude;
  final String? phone;
  final String mapsUrl;
  final String? directionsUrl;

  NearbyDoctor({
    required this.placeId,
    required this.name,
    required this.specialty,
    required this.address,
    this.isOpenNow,
    this.distanceMeters,
    this.latitude,
    this.longitude,
    this.phone,
    required this.mapsUrl,
    this.directionsUrl,
  });

  factory NearbyDoctor.fromJson(Map<String, dynamic> j) {
    return NearbyDoctor(
      placeId: j['placeId'] as String? ?? '',
      name: j['name'] as String? ?? 'Unknown',
      specialty: j['specialty'] as String? ?? '',
      address: j['address'] as String? ?? '',
      isOpenNow: j['isOpenNow'] as bool?,
      distanceMeters: (j['distanceMeters'] as num?)?.toInt(),
      latitude: (j['latitude'] as num?)?.toDouble(),
      longitude: (j['longitude'] as num?)?.toDouble(),
      phone: j['phone'] as String?,
      mapsUrl: j['mapsUrl'] as String? ?? '',
      directionsUrl: j['directionsUrl'] as String?,
    );
  }

  /// e.g. "350 m" or "2.4 km" — for display next to the doctor's name.
  String get distanceLabel {
    if (distanceMeters == null) return '';
    if (distanceMeters! < 1000) return '$distanceMeters m';
    return '${(distanceMeters! / 1000).toStringAsFixed(1)} km';
  }
}

/// Result of the combined specialist-match + nearby-search call — see
/// DoctorFinderService.findNearbyDoctors.
class DoctorSearchResult {
  final String specialist;
  final String specialistReason;
  final int radiusMeters;
  final List<NearbyDoctor> doctors;

  DoctorSearchResult({
    required this.specialist,
    required this.specialistReason,
    required this.radiusMeters,
    required this.doctors,
  });

  factory DoctorSearchResult.fromJson(Map<String, dynamic> j) {
    final list = (j['doctors'] as List?) ?? [];
    return DoctorSearchResult(
      specialist: j['specialist'] as String? ?? 'General Physician',
      specialistReason: j['specialistReason'] as String? ?? '',
      radiusMeters: (j['radiusMeters'] as num?)?.toInt() ?? 5000,
      doctors: list
          .map((e) => NearbyDoctor.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
