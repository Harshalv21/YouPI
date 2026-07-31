import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// Full-screen "pick a number" page -- matches the native contact-picker
/// look: search box on top, then a scrollable list of all device contacts
/// with an avatar + name + number. Tapping a row pops this screen and
/// returns the selected 10-digit number to the caller.
class RechargeContactPickerScreen extends StatefulWidget {
  const RechargeContactPickerScreen({super.key});

  @override
  State<RechargeContactPickerScreen> createState() =>
      _RechargeContactPickerScreenState();
}

class _RechargeContactPickerScreenState
    extends State<RechargeContactPickerScreen> {
  final _searchCtrl = TextEditingController();
  List<Contact> _allContacts = [];
  List<Contact> _visible = [];
  bool _loading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applyFilter);
    _loadContacts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    await FlutterContacts.permissions.request(PermissionType.read);
    final granted = await FlutterContacts.permissions.has(PermissionType.read);

    if (!granted) {
      setState(() {
        _permissionDenied = true;
        _loading = false;
      });
      return;
    }

    try {
      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
      final withPhones = contacts.where((c) => c.phones.isNotEmpty).toList();
      withPhones.sort((a, b) =>
          (a.displayName ?? '').toLowerCase().compareTo((b.displayName ?? '').toLowerCase()));
      setState(() {
        _allContacts = withPhones;
        _visible = withPhones;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _visible = _allContacts);
      return;
    }
    final digits = q.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _visible = _allContacts.where((c) {
        final name = (c.displayName ?? '').toLowerCase();
        if (name.contains(q)) return true;
        if (digits.isEmpty) return false;
        return c.phones.any((p) =>
            p.number.replaceAll(RegExp(r'\D'), '').contains(digits));
      }).toList();
    });
  }

  String _last10(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
  }

  void _pick(String number, [String? name]) {
    final clean = _last10(number);
    if (clean.length != 10) return;
    Navigator.of(context).pop(clean);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPrimary,
        title: Text('Mobile recharge', style: AppTextStyles.headlineMedium),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
    // Search box to filter the contacts list below
          // Search box to filter the contacts list below
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              style: AppTextStyles.bodyMedium,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search contacts',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _permissionDenied
                ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Contacts access denied. You can still type the number above and tap "Use this number".',
                style: AppTextStyles.bodyMedium,
                textAlign: TextAlign.center,
              ),
            )
                : _visible.isEmpty
                ? Center(
              child: Text('No contacts found', style: AppTextStyles.bodyMedium),
            )
                : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _visible.length,
              itemBuilder: (ctx, i) {
                final c = _visible[i];
                final name = c.displayName ?? '';
                final phone = c.phones.first.number;
                return ListTile(
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '#',
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary),
                    ),
                  ),
                  title: Text(name, style: AppTextStyles.bodyMedium),
                  subtitle: Text(phone, style: AppTextStyles.bodySmall),
                  onTap: () => _pick(phone, name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}