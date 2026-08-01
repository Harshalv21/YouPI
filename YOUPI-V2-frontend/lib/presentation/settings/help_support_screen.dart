import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_card.dart';

// Support inbox all three email tiles point to -- same address, different
// subject line per category so support can triage at a glance.
const String _supportEmail = 'connect@you-pi.in';

/// Opens the device's mail app via mailto: with the "to" address and
/// subject pre-filled. The "from" address is NOT something we set -- the
/// mail app fills that in automatically using whichever account is
/// already configured on the user's device (that's how mailto: links
/// work everywhere, not specific to this app).
Future<void> _openEmailSupport(BuildContext context, {required String subject}) async {
  final uri = Uri(scheme: 'mailto', path: _supportEmail, queryParameters: {'subject': subject});
  final opened = await launchUrl(uri);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open a mail app. Is one installed?')),
    );
  }
}

/// Opens WhatsApp with the support number and a pre-filled draft message
/// (the user still has to hit send -- WhatsApp's wa.me links can only
/// pre-fill what the USER sends, they can't inject an auto-reply from the
/// business side). Falls back to a SnackBar if WhatsApp isn't installed
/// and no browser can handle the wa.me link either.
// India number, so +91 is added here rather than baked into the raw digits.
const String _supportWhatsappNumber = '919109815006';

Future<void> _openWhatsappSupport(BuildContext context, String message) async {
  final uri = Uri.parse('https://wa.me/$_supportWhatsappNumber?text=${Uri.encodeComponent(message)}');
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open WhatsApp. Is it installed?')),
    );
  }
}

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Help & Support'), backgroundColor: AppColors.backgroundPrimary),
      body: ListView(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        children: [
          Text('We\'re here to help', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 6),
          Text(
            'Reach out to us for any query, complaint, or issue related to your account, recharges, gold investments, or loans.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          _WhatsAppTile(
            onTap: () => _openWhatsappSupport(
              context,
              'Hi Nexospendz Support team, this is regarding my YouPI app. I need some help.',
            ),
          ),
          const SizedBox(height: 20),
          Text('Or reach us by email', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          _SupportTile(
            icon: Icons.support_agent,
            title: 'Customer Support',
            subtitle: 'connect@you-pi.in',
            onTap: () => _openEmailSupport(context, subject: 'Customer Support Query'),
          ),
          const SizedBox(height: 12),
          _SupportTile(
            icon: Icons.report_problem_outlined,
            title: 'Complaints & Grievance',
            subtitle: 'connect@you-pi.in',
            onTap: () => _openEmailSupport(context, subject: 'Complaint / Grievance'),
          ),
          const SizedBox(height: 12),
          _SupportTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Queries',
            subtitle: 'connect@you-pi.in',
            onTap: () => _openEmailSupport(context, subject: 'Privacy Query'),
          ),
          const SizedBox(height: 24),
          Text(
            'For any support request, complaint, or privacy-related query, please contact us at connect@you-pi.in. We will assist you as soon as possible.',
            style: AppTextStyles.captionText,
          ),
        ],
      ),
    );
  }
}

class _SupportTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SupportTile({required this.icon, required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return YoupiCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
        ],
      ),
    );
  }
}

class _WhatsAppTile extends StatelessWidget {
  final VoidCallback onTap;
  const _WhatsAppTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return YoupiCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.chat, color: Color(0xFF25D366), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chat with us on WhatsApp', style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text('Fastest way to reach support · +91 91098 15006', style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
        ],
      ),
    );
  }
}