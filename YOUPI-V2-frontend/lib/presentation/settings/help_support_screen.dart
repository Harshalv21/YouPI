import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_card.dart';

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
          const _SupportTile(
            icon: Icons.support_agent,
            title: 'Customer Support',
            subtitle: 'support@you-pi.in',
          ),
          const SizedBox(height: 12),
          const _SupportTile(
            icon: Icons.report_problem_outlined,
            title: 'Complaints & Grievance',
            subtitle: 'grievance@you-pi.in',
          ),
          const SizedBox(height: 12),
          const _SupportTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Queries',
            subtitle: 'privacy@you-pi.in',
          ),
          const SizedBox(height: 24),
          Text(
            'For YouPi Credit loan complaints unresolved by our team, you can escalate to your Lending Partner\'s grievance officer (details in your Key Fact Statement) and, where applicable, RBI\'s integrated ombudsman mechanism.',
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

  const _SupportTile({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return YoupiCard(
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
        ],
      ),
    );
  }
}