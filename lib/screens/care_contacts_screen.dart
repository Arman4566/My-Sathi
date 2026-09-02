import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/care_contact.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/app_text.dart';

/// Lets the patient add a family member/caregiver's WhatsApp number so
/// the backend (backend/whatsapp_reminders.js) can message them if a
/// medicine dose looks missed, and ~30 minutes before an appointment.
/// Each contact can opt into either alert type independently.
class CareContactsScreen extends StatefulWidget {
  const CareContactsScreen({super.key});
  @override
  State<CareContactsScreen> createState() => _CareContactsScreenState();
}

class _CareContactsScreenState extends State<CareContactsScreen> {
  List<CareContact> _contacts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contacts = await DatabaseService.instance.getCareContacts();
    if (mounted) setState(() {
      _contacts = contacts;
      _loading = false;
    });
  }

  Future<void> _showAddDialog() async {
    final lang = context.read<SettingsService>().languageCode;
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool notifyMissedMedicine = true;
    bool notifyBeforeAppointment = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(AppText.t('care_contacts_title', lang)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: AppText.t('care_contact_name', lang)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: AppText.t('care_contact_phone', lang),
                    hintText: AppText.t('care_contact_phone_hint', lang),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(AppText.t('care_contact_notify_missed_medicine', lang),
                      style: const TextStyle(fontSize: 13)),
                  value: notifyMissedMedicine,
                  onChanged: (v) => setStateDialog(() => notifyMissedMedicine = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(AppText.t('care_contact_notify_before_appointment', lang),
                      style: const TextStyle(fontSize: 13)),
                  value: notifyBeforeAppointment,
                  onChanged: (v) => setStateDialog(() => notifyBeforeAppointment = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(AppText.t('cancel', lang))),
            ElevatedButton(
              onPressed: () async {
                final phone = phoneCtrl.text.trim();
                if (phone.isEmpty) return;
                final contact = CareContact(
                  id: const Uuid().v4(),
                  name: nameCtrl.text.trim(),
                  phone: phone,
                  notifyMissedMedicine: notifyMissedMedicine,
                  notifyBeforeAppointment: notifyBeforeAppointment,
                );
                await DatabaseService.instance.insertCareContact(contact);
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: Text(AppText.t('care_contact_add', lang)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(CareContact c) async {
    await DatabaseService.instance.deleteCareContact(c.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(AppText.t('care_contacts_title', lang))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: Text(AppText.t('care_contact_add', lang)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  AppText.t('care_contacts_subtitle', lang),
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (_contacts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      AppText.t('care_contact_empty', lang),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                else
                  ..._contacts.map((c) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(c.name.isEmpty ? c.phone : c.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.phone),
                              const SizedBox(height: 2),
                              Wrap(
                                spacing: 6,
                                children: [
                                  if (c.notifyMissedMedicine)
                                    _Chip(AppText.t('care_contact_notify_missed_medicine', lang)),
                                  if (c.notifyBeforeAppointment)
                                    _Chip(AppText.t('care_contact_notify_before_appointment', lang)),
                                ],
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () => _delete(c),
                          ),
                        ),
                      )),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppText.t('care_contact_whatsapp_note', lang),
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF5B7CFA).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF5B7CFA))),
    );
  }
}
