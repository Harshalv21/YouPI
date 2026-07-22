import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// A phone-number field that shows matching device contacts (name + number)
/// as the user types, GPay-style — tap a suggestion to fill the number.
///
/// Requires the `flutter_contacts` package:
///   flutter pub add flutter_contacts
///
/// Android: add to AndroidManifest.xml (flutter_contacts handles the
/// permission request at runtime, this is just the manifest declaration):
///   <uses-permission android:name="android.permission.READ_CONTACTS"/>
///
/// iOS: add to Info.plist:
///   <key>NSContactsUsageDescription</key>
///   <string>To let you pick a number to recharge from your contacts</string>
class ContactPickerField extends StatefulWidget {
  final TextEditingController controller;
  final void Function(String number, String? contactName)? onNumberSelected;

  const ContactPickerField({
    super.key,
    required this.controller,
    this.onNumberSelected,
  });

  @override
  State<ContactPickerField> createState() => _ContactPickerFieldState();
}

class _ContactPickerFieldState extends State<ContactPickerField> {
  List<Contact> _allContacts = [];
  List<_ContactMatch> _matches = [];
  bool _permissionDenied = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onQueryChanged);
    _maybeLoadContacts();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onQueryChanged);
    super.dispose();
  }

  Future<void> _maybeLoadContacts() async {
    // Don't prompt for permission just for opening the field -- only once
    // the user actually starts typing digits, so we're not asking for
    // contacts access before they've shown any intent to use it.
    if (_allContacts.isNotEmpty || _loading) return;
    setState(() => _loading = true);

<<<<<<< Updated upstream
    // flutter_contacts 2.3.0 restructured the API into sub-APIs
    // (FlutterContacts.permissions, FlutterContacts.getAll(...)) --
    // there's no top-level requestPermission()/getContacts() anymore.
    // Using .request() then .has() (rather than parsing the returned
    // PermissionStatus directly) keeps this resilient to that enum's
    // exact member names, which we haven't needed to pin down.
    await FlutterContacts.permissions.request(PermissionType.read);
    final granted = await FlutterContacts.permissions.has(PermissionType.read);
=======
    final status = await FlutterContacts.permissions.request(PermissionType.read);
    final granted = status == PermissionStatus.granted || status == PermissionStatus.limited;
>>>>>>> Stashed changes
    if (!granted) {
      setState(() {
        _permissionDenied = true;
        _loading = false;
      });
      return;
    }

    try {
<<<<<<< Updated upstream
      // Name + phone only -- matches the old `withProperties: true`
      // intent closely enough for this field's purpose (name + number
      // suggestions), without pulling photos/emails/etc we don't use.
      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
=======
      final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone});
>>>>>>> Stashed changes
      setState(() {
        _allContacts = contacts.where((c) => c.phones.isNotEmpty).toList();
        _loading = false;
      });
      _onQueryChanged();
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _onQueryChanged() {
    final query = widget.controller.text.trim();

    if (query.isEmpty || _allContacts.isEmpty) {
      if (_matches.isNotEmpty) setState(() => _matches = []);
      return;
    }

    // Kick off a permission/load attempt the first time the user types,
    // in case initState's silent check hasn't resolved yet.
    if (_allContacts.isEmpty && !_loading && !_permissionDenied) {
      _maybeLoadContacts();
    }

    final digitsOnly = query.replaceAll(RegExp(r'\D'), '');
    final queryLower = query.toLowerCase();

    final matches = <_ContactMatch>[];
    for (final c in _allContacts) {
      for (final p in c.phones) {
        final normalized = p.number.replaceAll(RegExp(r'\D'), '');
        // Match on trailing digits (handles +91 prefixes) or on name.
        final numberMatches = digitsOnly.isNotEmpty &&
            normalized.length >= digitsOnly.length &&
            normalized.endsWith(digitsOnly);
        final displayName = c.displayName ?? '';
        final nameMatches =
            queryLower.isNotEmpty && displayName.toLowerCase().contains(queryLower);

        if (numberMatches || nameMatches) {
          // Keep only the last 10 digits (Indian mobile numbers) for a
          // clean display/fill value, dropping country code if present.
          final last10 = normalized.length >= 10
              ? normalized.substring(normalized.length - 10)
              : normalized;
          matches.add(_ContactMatch(name: displayName, number: last10));
          break; // one match per contact is enough
        }
      }
      if (matches.length >= 6) break; // cap suggestions, avoid a huge list
    }

    setState(() => _matches = matches);
  }

  void _select(_ContactMatch match) {
    widget.controller.text = match.number;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: widget.controller.text.length),
    );
    setState(() => _matches = []);
    widget.onNumberSelected?.call(match.number, match.name);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            prefixText: '+91 ',
            hintText: 'Enter mobile number or name',
            counterText: '',
            suffixIcon: _loading
                ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
                : null,
          ),
        ),
        if (_permissionDenied && widget.controller.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Contacts access denied — you can still type the number manually.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ),
        if (_matches.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: AppColors.backgroundSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _matches.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.divider),
              itemBuilder: (ctx, i) {
                final m = _matches[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    child: Text(
                      m.name.isNotEmpty ? m.name[0].toUpperCase() : '#',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
                    ),
                  ),
                  title: Text(m.name, style: AppTextStyles.bodyMedium),
                  subtitle: Text('+91 ${m.number}', style: AppTextStyles.bodySmall),
                  onTap: () => _select(m),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ContactMatch {
  final String name;
  final String number;
  _ContactMatch({required this.name, required this.number});
}