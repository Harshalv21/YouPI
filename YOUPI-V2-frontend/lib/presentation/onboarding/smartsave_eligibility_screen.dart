import 'package:flutter/material.dart';
import 'confetti_burst.dart';
import 'onboarding_questions_screen.dart' show OnboardingAnswers;

// ── App palette (matches onboarding_questions_screen.dart) ──
const _bg = Color(0xFF0B0D12);
const _card = Color(0xFF1A1D24);
const _accent = Color(0xFF1CE8A4);
const _accentDark = Color(0xFF08281D);
const _text = Colors.white;
const _muted = Color(0xFF7D818A);

/// Very lightweight, client-side heuristic — NOT the real eligibility
/// check. Actual SmartSave eligibility (benefit-signature match, NBFC
/// sign-off thresholds, etc.) happens later against the backend once the
/// user is registered. This is purely to decide which message this
/// pre-auth screen shows, based on whatever they answered.
///
/// Currently: eligible if they answered at least one question. Replace
/// this with a real call once the backend exposes a pre-auth eligibility
/// signal, if that's ever needed — right now it's just about keeping the
/// screen honest (an empty answer set shouldn't claim eligibility).
bool computeSmartSaveEligibility(OnboardingAnswers answers) {
  return answers.selections.values.any((v) => v.isNotEmpty);
}

class SmartSaveEligibilityScreen extends StatefulWidget {
  final bool isEligible;
  final VoidCallback onContinue;

  const SmartSaveEligibilityScreen({
    super.key,
    required this.isEligible,
    required this.onContinue,
  });

  @override
  State<SmartSaveEligibilityScreen> createState() => _SmartSaveEligibilityScreenState();
}

class _SmartSaveEligibilityScreenState extends State<SmartSaveEligibilityScreen> {
  bool _showConfetti = true;

  @override
  void initState() {
    super.initState();
    // Matches ConfettiBurst's default totalDuration -- remove the widget
    // from the tree once it's finished rather than leaving an idle
    // CustomPaint around indefinitely.
    Future.delayed(const Duration(milliseconds: 4300), () {
      if (mounted) setState(() => _showConfetti = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: _accent, width: 2),
                      ),
                      child: const Icon(Icons.savings_rounded, color: _accent, size: 44),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      widget.isEligible
                          ? "You're eligible for SmartSave"
                          : "Your profile is ready",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.isEligible
                          ? "Based on your monthly bills, SmartSave can turn small, regular recharges into real savings — automatically, without you having to think about it."
                          : "We'll use what you shared to personalize your account. You can explore SmartSave anytime from your dashboard.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _muted, fontSize: 14.5, height: 1.5),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_rounded, color: _accent, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.isEligible
                                  ? 'SmartSave will be ready as soon as your account is set up.'
                                  : 'Finish setting up your account to unlock SmartSave.',
                              style: const TextStyle(color: _text, fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: widget.onContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: _accentDark,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: const Text('Continue',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.isEligible && _showConfetti)
            const Positioned.fill(child: ConfettiBurst()),
        ],
      ),
    );
  }
}