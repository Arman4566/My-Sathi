import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/nearby_doctor.dart';
import '../services/doctor_finder_service.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

/// Quick-pick specialties shown as chips so a patient who already knows
/// what they need can skip typing a symptom (and skip the AI matching
/// call on the backend entirely). Kept in sync with the fixed list in
/// backend/doctors.js — the backend falls back to "General Physician" for
/// anything it doesn't recognize, so these must be spelled identically.
const List<String> _quickSpecialties = [
  'General Physician',
  'Dentist',
  'Pediatrician',
  'Gynecologist',
  'Dermatologist',
  'Cardiologist',
  'ENT Specialist',
  'Orthopedist',
  'Ophthalmologist',
  'Psychiatrist',
];

class FindDoctorsScreen extends StatefulWidget {
  const FindDoctorsScreen({super.key});
  @override
  State<FindDoctorsScreen> createState() => _FindDoctorsScreenState();
}

class _FindDoctorsScreenState extends State<FindDoctorsScreen> {
  final _conditionController = TextEditingController();
  String? _selectedSpecialty;
  bool _searching = false;
  String? _errorMessage;
  DoctorSearchResult? _result;
  double _radiusMeters = 5000;

  @override
  void dispose() {
    _conditionController.dispose();
    super.dispose();
  }

  Future<void> _search({double? radiusOverride}) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _errorMessage = null;
    });

    try {
      final position = await DoctorFinderService.instance.getCurrentLocation();
      final radius = radiusOverride ?? _radiusMeters;
      final result = await DoctorFinderService.instance.findNearbyDoctors(
        latitude: position.latitude,
        longitude: position.longitude,
        specialty: _selectedSpecialty,
        medicalCondition: _selectedSpecialty == null ? _conditionController.text : null,
        radiusMeters: radius,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _radiusMeters = radius;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _searching = false;
      });
    }
  }

  Future<void> _widenSearch() async {
    await _search(radiusOverride: (_radiusMeters * 2).clamp(500, 50000));
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(AppText.t('find_doctors', lang))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Text(
              AppText.t('find_doctors_desc', lang),
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 18),
            Text(AppText.t('describe_symptom_label', lang),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _conditionController,
              maxLines: 2,
              enabled: _selectedSpecialty == null,
              decoration: InputDecoration(
                hintText: AppText.t('describe_symptom_hint', lang),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_selectedSpecialty != null) {
                  setState(() => _selectedSpecialty = null);
                }
              },
            ),
            const SizedBox(height: 16),
            Text(AppText.t('or_pick_specialty', lang),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickSpecialties.map((s) {
                final selected = _selectedSpecialty == s;
                return ChoiceChip(
                  label: Text(s),
                  selected: selected,
                  onSelected: (sel) {
                    setState(() {
                      _selectedSpecialty = sel ? s : null;
                      if (sel) _conditionController.clear();
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _searching ? null : () => _search(),
                icon: _searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search),
                label: Text(_searching
                    ? AppText.t('finding_doctors', lang)
                    : AppText.t('search_nearby_doctors', lang)),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppText.t('find_doctors_disclaimer', lang),
                      style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_errorMessage != null) _errorCard(lang),
            if (_result != null) ..._resultSection(lang),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(String lang) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _resultSection(String lang) {
    final result = _result!;
    final widgets = <Widget>[
      Text(
        AppText.t('showing_specialist', lang).replaceFirst('{specialist}', result.specialist),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      if (result.specialistReason.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(result.specialistReason, style: TextStyle(color: Theme.of(context).hintColor)),
      ],
      const SizedBox(height: 4),
      Text(
        AppText.t('osm_data_note', lang),
        style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
      ),
      const SizedBox(height: 14),
    ];

    if (result.doctors.isEmpty) {
      widgets.add(Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Icon(Icons.search_off, color: Theme.of(context).hintColor, size: 32),
              const SizedBox(height: 8),
              Text(AppText.t('no_doctors_found', lang), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _searching ? null : _widenSearch,
                child: Text(AppText.t('widen_search', lang)),
              ),
            ],
          ),
        ),
      ));
    } else {
      widgets.addAll(result.doctors.map((d) => _doctorCard(d, lang)));
      widgets.add(const SizedBox(height: 8));
      widgets.add(Center(
        child: TextButton(
          onPressed: _searching ? null : _widenSearch,
          child: Text(AppText.t('widen_search', lang)),
        ),
      ));
    }

    return widgets;
  }

  Widget _doctorCard(NearbyDoctor d, String lang) {
    final hasPhone = d.phone != null && d.phone!.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(d.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                if (d.isOpenNow != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: d.isOpenNow!
                          ? Colors.green.withOpacity(0.15)
                          : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      d.isOpenNow!
                          ? AppText.t('open_now', lang)
                          : AppText.t('closed_now', lang),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: d.isOpenNow! ? Colors.green.shade800 : Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(d.specialty,
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13)),
            if (d.distanceMeters != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.social_distance_outlined, size: 16, color: Theme.of(context).hintColor),
                  const SizedBox(width: 4),
                  Text(d.distanceLabel,
                      style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
                ],
              ),
            ],
            if (d.address.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on_outlined, size: 16, color: Theme.of(context).hintColor),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(d.address,
                        style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => DoctorFinderService.instance.openDirections(d),
                    icon: const Icon(Icons.directions_outlined, size: 18),
                    label: Text(AppText.t('directions', lang)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: hasPhone ? () => DoctorFinderService.instance.call(d) : null,
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: Text(AppText.t('call', lang)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
