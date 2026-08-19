import 'package:flutter/material.dart';

// SmartSave -- FRONTEND ONLY (mock data). Backend recommendation API
// (Dikshi Finlease benefit-signature matching) is not ready yet.
// Once the backend endpoint exists, replace mock instances of this model
// with ones built from the real API response (e.g. vm.smartSaveRecommendations).

class SmartSavePlanBenefit {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const SmartSavePlanBenefit({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });
}

class SmartSaveRecommendation {
  final String displayName; // contact name or mobile number
  final String mobileNumber;
  final String operatorName; // e.g. "Jio", "Airtel", "Vi"
  final int currentPlanAmount; // what the user currently pays per recharge
  final int currentPlanFrequencyMonths; // how many months this pattern repeats
  final int suggestedPlanAmount; // total price of the longer-duration plan
  final int suggestedPlanValidityDays;
  final int monthlyInstalment; // what the user pays per month via SmartSave
  final int totalSavings;
  final List<SmartSavePlanBenefit> benefits; // "What you get" list
  final int smartInvestBonusRupees; // digital gold auto-invested per recharge

  const SmartSaveRecommendation({
    required this.displayName,
    required this.mobileNumber,
    required this.operatorName,
    required this.currentPlanAmount,
    required this.currentPlanFrequencyMonths,
    required this.suggestedPlanAmount,
    required this.suggestedPlanValidityDays,
    required this.monthlyInstalment,
    required this.totalSavings,
    required this.benefits,
    this.smartInvestBonusRupees = 5,
  });

  // Normal way -- what the user would pay if they kept recharging at the
  // current cadence for the same number of instalments as the SmartSave plan.
  int get normalWayTotal => currentPlanAmount * currentPlanFrequencyMonths;

  // SmartSave way -- total paid across all instalments.
  int get smartSaveWayTotal => monthlyInstalment * currentPlanFrequencyMonths;

  int get computedSavings => normalWayTotal - smartSaveWayTotal;

  int get cycleDays => currentPlanFrequencyMonths > 0
      ? (suggestedPlanValidityDays / currentPlanFrequencyMonths).round()
      : suggestedPlanValidityDays;
}

const List<SmartSaveRecommendation> mockSmartSaveRecommendations = [
  SmartSaveRecommendation(
    displayName: 'Gautam',
    mobileNumber: '6386416861',
    operatorName: 'Jio',
    currentPlanAmount: 349,
    currentPlanFrequencyMonths: 3,
    suggestedPlanAmount: 899,
    suggestedPlanValidityDays: 84,
    monthlyInstalment: 300,
    totalSavings: 147,
    benefits: [
      SmartSavePlanBenefit(
        icon: Icons.bar_chart_rounded,
        iconColor: Color(0xFFFF8A00),
        label: 'Data',
        value: '2 GB / day (5G + 4G)',
      ),
      SmartSavePlanBenefit(
        icon: Icons.call_rounded,
        iconColor: Color(0xFF2E7D32),
        label: 'Calls',
        value: 'Unlimited Local, STD & Roaming',
      ),
      SmartSavePlanBenefit(
        icon: Icons.sms_rounded,
        iconColor: Color(0xFF2E7D32),
        label: 'SMS',
        value: '100 SMS / day',
      ),
      SmartSavePlanBenefit(
        icon: Icons.auto_awesome_rounded,
        iconColor: Color(0xFFFFC107),
        label: 'Google Gemini Pro',
        value: 'Free with plan',
      ),
      SmartSavePlanBenefit(
        icon: Icons.calendar_month_rounded,
        iconColor: Color(0xFFE53935),
        label: 'Validity',
        value: '84 days (3 × 28-day cycles)',
      ),
      SmartSavePlanBenefit(
        icon: Icons.autorenew_rounded,
        iconColor: Color(0xFFFF8A00),
        label: 'Data Rollover',
        value: 'Unused data does not rollover',
      ),
    ],
  ),
  SmartSaveRecommendation(
    displayName: '9123456780',
    mobileNumber: '9123456780',
    operatorName: 'Airtel',
    currentPlanAmount: 239,
    currentPlanFrequencyMonths: 2,
    suggestedPlanAmount: 719,
    suggestedPlanValidityDays: 84,
    monthlyInstalment: 220,
    totalSavings: 38,
    benefits: [
      SmartSavePlanBenefit(
        icon: Icons.bar_chart_rounded,
        iconColor: Color(0xFFFF8A00),
        label: 'Data',
        value: '1.5 GB / day (5G + 4G)',
      ),
      SmartSavePlanBenefit(
        icon: Icons.call_rounded,
        iconColor: Color(0xFF2E7D32),
        label: 'Calls',
        value: 'Unlimited Local, STD & Roaming',
      ),
      SmartSavePlanBenefit(
        icon: Icons.sms_rounded,
        iconColor: Color(0xFF2E7D32),
        label: 'SMS',
        value: '100 SMS / day',
      ),
      SmartSavePlanBenefit(
        icon: Icons.calendar_month_rounded,
        iconColor: Color(0xFFE53935),
        label: 'Validity',
        value: '84 days (2 × 42-day cycles)',
      ),
      SmartSavePlanBenefit(
        icon: Icons.autorenew_rounded,
        iconColor: Color(0xFFFF8A00),
        label: 'Data Rollover',
        value: 'Unused data does not rollover',
      ),
    ],
  ),
];