import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import '../../data/repositories/user_repository.dart';

/// Settings > PAN Details — read-only view of the user's verified PAN,
/// matching the "view your saved document" pattern GPay/PhonePe use for
/// KYC info (masked value, verified badge, no edit-in-place — re-verify
/// goes through the same flow as first-time verification).
class PanDetailsScreen extends StatefulWidget {
  const PanDetailsScreen({super.key});

  @override
  State<PanDetailsScreen> createState() => _PanDetailsScreenState();
}

class _PanDetailsScreenState extends State<PanDetailsScreen> {
  final _userRepo = UserRepository();
  KycDetailsResult? _details;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await _userRepo.getKycDetails();
      setState(() => _details = result);
    } catch (e) {
      setState(() => _error = 'Could not load your PAN details. Pull to retry.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _details;
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPrimary,
        title: Text('PAN Details', style: AppTextStyles.headlineSmall),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: _loading
            ? const Center(child: Padding(
            padding: EdgeInsets.only(top: 100),
            child: CircularProgressIndicator(color: AppColors.primary)))
            : ListView(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
              ),
            if (d == null || !d.panVerified) ...[
              YoupiCard(
                child: Column(
                  children: [
                    const Icon(Icons.badge_outlined, color: AppColors.textSecondary, size: 36),
                    const SizedBox(height: 10),
                    Text('No PAN verified yet', style: AppTextStyles.labelLarge),
                    const SizedBox(height: 4),
                    Text('Complete KYC to add and verify your PAN.',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    YoupiButton(
                      label: 'Start KYC',
                      onPressed: () => context.push('/kyc/intro'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              YoupiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.badge_rounded, color: AppColors.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('PAN Card', style: AppTextStyles.labelLarge),
                              Text('Verified via Eko', style: AppTextStyles.captionText),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 14),
                              const SizedBox(width: 4),
                              Text('Verified', style: AppTextStyles.labelSmall.copyWith(color: AppColors.success)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28, color: AppColors.divider),
                    _DetailRow(label: 'PAN Number', value: d.panNumberMasked ?? '—'),
                    const SizedBox(height: 12),
                    _DetailRow(label: 'Name on PAN', value: d.panHolderName ?? '—'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        Text(value, style: AppTextStyles.labelLarge),
      ],
    );
  }
}