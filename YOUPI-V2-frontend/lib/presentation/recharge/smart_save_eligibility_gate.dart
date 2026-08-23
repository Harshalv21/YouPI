import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

// SmartSave eligibility gate -- FRONTEND ONLY (mock). Shown instead of
// SmartSave recommendations when the user hasn't unlocked SmartSave yet.
// Backend eligibility check (2 consecutive months of YouPi recharges) is
// not ready -- see mockSmartSaveEligible below. Swap that for a real
// vm.isSmartSaveEligible (from RechargeViewModel) once the backend
// endpoint exists.
const bool mockSmartSaveEligible = false;

const Color _smartSaveGatePurple = Color(0xFF9C7CFF);

class SmartSaveEligibilityGate extends StatelessWidget {
  final VoidCallback onRechargeNow;
  const SmartSaveEligibilityGate({super.key, required this.onRechargeNow});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: _smartSaveGatePurple.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _smartSaveGatePurple.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.calendar_month_rounded, size: 56, color: _smartSaveGatePurple.withOpacity(0.9)),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundPrimary,
                      shape: BoxShape.circle,
                      border: Border.all(color: _smartSaveGatePurple),
                    ),
                    child: Icon(Icons.lock_rounded, size: 16, color: _smartSaveGatePurple),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "You're not eligible for SmartSave yet!",
            textAlign: TextAlign.center,
            style: AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Keep recharging with YouPi to unlock SmartSave and enjoy easy EMI payments.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onRechargeNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: _smartSaveGatePurple,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'Recharge Now',
                style: AppTextStyles.labelLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}