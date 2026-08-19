import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import 'smart_save_recommendation.dart';

// SmartSave Plan detail screen -- FRONTEND ONLY (mock data), opened from the
// "View SmartSave Plan" button on the recharge home screen. Payment dates,
// the "Pay & Activate" action, and the activated state are all mocked here;
// once the backend eNACH/UPI-Autopay mandate flow exists, replace with a real
// payment call + real mandate status.
const Color _smartSaveGreenDark = Color(0xFF0E4B33);
const Color _smartSaveGreenLight = Color(0xFF1E9E63);
const Color _smartSaveAmountYellow = Color(0xFFFFD93D);
const Color _normalWayRed = Color(0xFFE53935);

class SmartSavePlanDetailScreen extends StatefulWidget {
  final SmartSaveRecommendation recommendation;
  const SmartSavePlanDetailScreen({super.key, required this.recommendation});

  @override
  State<SmartSavePlanDetailScreen> createState() => _SmartSavePlanDetailScreenState();
}

class _SmartSavePlanDetailScreenState extends State<SmartSavePlanDetailScreen> {
  bool _agreed = false;
  bool _activated = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.recommendation;
    final instalmentCount = r.currentPlanFrequencyMonths;
    final savings = r.computedSavings;

    // Auto-debit dates -- Day 0 (today), then every `cycleDays` after that.
    final dueDates = List.generate(
      instalmentCount,
      (i) => DateTime.now().add(Duration(days: r.cycleDays * i)),
    );
    final futureDatesText = dueDates
        .skip(1)
        .map(_formatDate)
        .join(' and ');

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('SmartSave Plan', style: AppTextStyles.headlineMedium),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary),
              ),
              child: Text(
                'SAVE ₹$savings',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---------------- Savings hero card ----------------
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_smartSaveGreenLight, _smartSaveGreenDark],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOU ARE SAVING',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: Colors.white.withOpacity(0.85),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹$savings',
                      style: AppTextStyles.headlineLarge.copyWith(
                        color: _smartSaveAmountYellow,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'vs ${instalmentCount}× monthly ₹${r.currentPlanAmount}',
                        style: AppTextStyles.bodySmall.copyWith(color: Colors.white.withOpacity(0.85)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Same ${r.suggestedPlanValidityDays}-day plan · Zero benefit compromise',
                  style: AppTextStyles.bodySmall.copyWith(color: Colors.white.withOpacity(0.85)),
                ),
                const SizedBox(height: 16),
                Divider(color: Colors.white.withOpacity(0.2), height: 1),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Normal way',
                              style: AppTextStyles.captionText.copyWith(color: Colors.white.withOpacity(0.75))),
                          const SizedBox(height: 4),
                          Text(
                            '₹${_formatAmount(r.normalWayTotal)}',
                            style: AppTextStyles.labelLarge.copyWith(
                              color: Colors.white.withOpacity(0.6),
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SmartSave way',
                              style: AppTextStyles.captionText.copyWith(color: Colors.white.withOpacity(0.75))),
                          const SizedBox(height: 4),
                          Text(
                            '₹${_formatAmount(r.smartSaveWayTotal)}',
                            style: AppTextStyles.headlineSmall.copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ---------------- "What you get" card ----------------
          Container(
            decoration: BoxDecoration(
              color: AppColors.backgroundCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('What you get', style: AppTextStyles.headlineSmall),
                      const SizedBox(height: 2),
                      Text(
                        '${r.operatorName} ${r.suggestedPlanValidityDays}-day plan — all benefits included',
                        style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Divider(color: AppColors.textSecondary.withOpacity(0.1), height: 1),
                ...r.benefits.map((b) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: b.iconColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(b.icon, size: 20, color: b.iconColor),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b.label,
                                    style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)),
                                const SizedBox(height: 2),
                                Text(b.value, style: AppTextStyles.labelLarge),
                              ],
                            ),
                          ),
                          Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                        ],
                      ),
                    ),
                    if (b != r.benefits.last)
                      Divider(color: AppColors.textSecondary.withOpacity(0.06), height: 1, indent: 66),
                  ],
                )),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ---------------- "Why SmartSave?" card ----------------
          Container(
            decoration: BoxDecoration(
              color: AppColors.backgroundCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Why SmartSave?', style: AppTextStyles.headlineSmall),
                ),
                Divider(color: AppColors.textSecondary.withOpacity(0.1), height: 1),

                // Normal way vs SmartSave way comparison
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          color: _normalWayRed.withOpacity(0.08),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text('😐 ', style: TextStyle(fontSize: 13)),
                                  Text(
                                    'NORMAL WAY',
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: _normalWayRed,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _comparisonLine(
                                '✗ Pay ₹${r.currentPlanAmount} × $instalmentCount = ₹${_formatAmount(r.normalWayTotal)}',
                                _normalWayRed,
                              ),
                              _comparisonLine('✗ $instalmentCount separate recharges', _normalWayRed),
                              _comparisonLine('✗ Risk of forgetting', _normalWayRed),
                              _comparisonLine('✗ Zero savings', _normalWayRed),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          color: AppColors.primary.withOpacity(0.08),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.bolt_rounded, size: 14, color: AppColors.primary),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      'SMARTSAVE WAY',
                                      style: AppTextStyles.labelSmall.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _comparisonLine(
                                '✓ Pay ₹${r.monthlyInstalment} × $instalmentCount = ₹${_formatAmount(r.smartSaveWayTotal)}',
                                AppColors.primary,
                              ),
                              _comparisonLine('✓ Auto-managed by YouPI', AppColors.primary),
                              _comparisonLine('✓ Never miss a recharge', AppColors.primary),
                              _comparisonLine('✓ Save ₹$savings every cycle', AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // SmartInvest bonus banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  color: const Color(0xFFFFC107).withOpacity(0.12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🏦', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
                            children: [
                              TextSpan(
                                text: 'SmartInvest bonus: ',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              TextSpan(
                                text:
                                    '₹${r.smartInvestBonusRupees} in 24K digital gold invested automatically on each recharge',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // UPI AutoPay mandate info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lock_rounded, size: 16, color: Colors.blueAccent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
                              children: [
                                TextSpan(
                                  text: instalmentCount > 1
                                      ? '${dueDates.skip(1).map((d) => 'Day ${r.cycleDays * (dueDates.indexOf(d))}').join(' and ')} payments are auto-collected via '
                                      : 'Future payments are auto-collected via ',
                                ),
                                const TextSpan(
                                  text: 'UPI AutoPay mandate',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const TextSpan(
                                  text: ' — approved once, runs silently. Cancel anytime before the due date.',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (!_activated) ...[
                  // Agreement checkbox
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _agreed,
                          activeColor: AppColors.primary,
                          onChanged: (v) => setState(() => _agreed = v ?? false),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              instalmentCount > 1
                                  ? 'I agree to pay ₹${r.monthlyInstalment} on $futureDatesText via UPI AutoPay mandate. I understand the plan activates immediately.'
                                  : 'I agree to the SmartSave payment terms. I understand the plan activates immediately.',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Pay & Activate button (mock -- no real payment/mandate call yet)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _agreed ? () => setState(() => _activated = true) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor: AppColors.textSecondary.withOpacity(0.15),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bolt_rounded,
                                size: 18,
                                color: _agreed ? AppColors.backgroundPrimary : AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Text(
                              'Pay ₹${r.monthlyInstalment} & Activate SmartSave',
                              style: AppTextStyles.labelLarge.copyWith(
                                color: _agreed ? AppColors.backgroundPrimary : AppColors.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // ---------------- Activated success state ----------------
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primary),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.check_rounded, color: AppColors.backgroundPrimary, size: 24),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'SmartSave Activated!',
                            style: AppTextStyles.headlineSmall.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${r.operatorName} ${r.suggestedPlanValidityDays}-day plan activated · '
                            'Next payment ${instalmentCount > 1 ? _formatDate(dueDates[1]) : "—"}',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _comparisonLine(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: AppTextStyles.captionText.copyWith(color: color),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  // Simple 3-digit comma grouping (e.g. 1047 -> "1,047"). Fine for the
  // recharge amounts shown here (well under ₹1 lakh); switch to a proper
  // Indian lakh/crore grouping later if larger amounts need it.
  String _formatAmount(int amount) {
    final s = amount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      buffer.write(s[i]);
      final remaining = s.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }
}