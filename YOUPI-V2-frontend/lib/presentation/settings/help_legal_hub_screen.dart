import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_card.dart';

/// Central "Help & Legal" hub, reached from Profile/Settings. Replaces
/// having Support and Legal items scattered as flat rows on the main
/// Settings screen -- groups them behind one entry point instead, and
/// gives Support (FAQ, Contact) a lighter two-card treatment separate
/// from Legal's plain list-of-links treatment.
class HelpLegalHubScreen extends StatelessWidget {
  const HelpLegalHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Help & Legal'), backgroundColor: AppColors.backgroundPrimary),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('How can we help you?', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 14),

          // Search jumps straight into the FAQ screen's own search field
          // rather than duplicating search logic here.
          GestureDetector(
            onTap: () => context.push('/invest/gold/faqs'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.backgroundCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(children: [
                const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 18),
                const SizedBox(width: 10),
                Text('Search help', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
              ]),
            ),
          ),
          const SizedBox(height: 24),

          Text('SUPPORT', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary, letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _HubCard(
              icon: Icons.quiz_outlined,
              label: 'FAQ',
              onTap: () => context.push('/invest/gold/faqs'),
            )),
            const SizedBox(width: 12),
            Expanded(child: _HubCard(
              icon: Icons.headset_mic_outlined,
              label: 'Contact Support',
              onTap: () => context.push('/settings/help-support'),
            )),
          ]),

          const SizedBox(height: 24),
          Text('AUGMONT', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary, letterSpacing: 1)),
          const SizedBox(height: 8),
          _HubRow(
            label: 'About Augmont',
            onTap: () => context.push('/invest/gold/about-augmont'),
          ),

          const SizedBox(height: 24),
          Text('LEGAL', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary, letterSpacing: 1)),
          const SizedBox(height: 8),
          _SettingsGroup(rows: [
            // Augmont's gold-specific T&C -- not YouPI's general app T&C,
            // by explicit choice: this hub sits directly off the Augmont
            // gold flow's Legal section.
            ('Terms & Conditions', '/invest/gold/terms'),
            ('Privacy Policy', '/settings/privacy-policy'),
            ('Refund Policy', '/settings/refund-policy'),
          ]),
        ]),
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _HubCard({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return YoupiCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(height: 10),
        Text(label, style: AppTextStyles.labelLarge),
      ]),
    );
  }
}

class _HubRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _HubRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return YoupiCard(
      onTap: onTap,
      child: Row(children: [
        Expanded(child: Text(label, style: AppTextStyles.labelLarge)),
        const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
      ]),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<(String, String)> rows;
  const _SettingsGroup({required this.rows});

  @override
  Widget build(BuildContext context) {
    return YoupiCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.divider),
            InkWell(
              onTap: () => context.push(rows[i].$2),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Expanded(child: Text(rows[i].$1, style: AppTextStyles.labelLarge)),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}