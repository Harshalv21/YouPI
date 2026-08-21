import 'package:flutter/material.dart';
import 'confetti_burst.dart';

/// Very lightweight, client-side heuristic — NOT the real eligibility
/// check. Actual SmartSave eligibility (benefit-signature match, NBFC
/// sign-off thresholds, etc.) happens later against the backend once the
/// user is registered. This only decides whether the summary page
/// celebrates with confetti.
///
/// Moved here (was previously in the now-removed dedicated "SmartSave
/// eligibility" screen) per director's instruction: that separate page
/// is gone from the flow, but the underlying eligibility check is still
/// useful to gate the celebration on the summary page itself.
bool computeSmartSaveEligibility(OnboardingAnswers answers) {
  return answers.selections.values.any((v) => v.isNotEmpty);
}

/// YouPi — Financial Profile Onboarding (5 tap-only questions)
///
/// IMPORTANT: this screen runs BEFORE phone number / OTP, so there is no
/// logged-in user yet — no backend call happens here. Answers are collected
/// in memory and handed back via [onComplete]. The caller is responsible for
/// navigating to phone entry next, and for actually submitting the answers
/// to the backend AFTER OTP verification succeeds (see OnboardingAnswerCache
/// below for a simple way to carry them across screens).
///
/// Theme matches the live app: dark #0B0D12 bg, #1A1D24 cards,
/// #1CE8A4 teal accent (NOT the purple of the reference shots).

// ── App palette (same tokens as recharge/invest screens) ──
const _bg = Color(0xFF0B0D12);
const _card = Color(0xFF1A1D24);
const _cardSelected = Color(0xFF12241E);
const _accent = Color(0xFF1CE8A4);
const _accentDark = Color(0xFF08281D);
const _text = Colors.white;
const _muted = Color(0xFF7D818A);
const _divider = Color(0xFF2A2E38);

// ── Data model ──

class OnboardingQuestion {
  final String id;
  final String title;
  final String helper;
  final bool multiSelect;
  final bool allowOther;
  final List<OnboardingOption> options;

  const OnboardingQuestion({
    required this.id,
    required this.title,
    required this.helper,
    required this.options,
    this.multiSelect = false,
    this.allowOther = false,
  });
}

class OnboardingOption {
  final String id;
  final String label;
  final IconData icon;
  const OnboardingOption(this.id, this.label, this.icon);
}

const _questions = <OnboardingQuestion>[
  OnboardingQuestion(
    id: 'monthly_bills',
    title: 'What do you pay for every month?',
    helper: 'This helps us suggest the right bills to save on.',
    multiSelect: true,
    options: [
      OnboardingOption('mobile', 'Mobile recharge', Icons.smartphone),
      OnboardingOption('wifi', 'Wifi / Broadband', Icons.wifi),
      OnboardingOption('ott', 'OTT (Netflix, Hotstar…)', Icons.play_circle_outline),
      OnboardingOption('dth', 'Cable / DTH', Icons.tv),
    ],
  ),
  OnboardingQuestion(
    id: 'bill_amount',
    title: 'Roughly how much do these add up to in a month?',
    helper: 'This sets your SmartSave instalment size.',
    options: [
      OnboardingOption('lt300', 'Under ₹300', Icons.payments_outlined),
      OnboardingOption('300_699', '₹300 – ₹699', Icons.account_balance_wallet_outlined),
      OnboardingOption('700_1499', '₹700 – ₹1,499', Icons.credit_card),
      OnboardingOption('gt1500', '₹1,500+', Icons.savings_outlined),
    ],
  ),
  OnboardingQuestion(
    id: 'income_pattern',
    title: 'How does money reach you?',
    helper: 'Helps us pick the right debit cadence and improves your YouPi Credit eligibility.',
    options: [
      OnboardingOption('salary', 'Fixed salary date', Icons.calendar_month),
      OnboardingOption('daily', 'Daily or weekly earning', Icons.currency_rupee),
      OnboardingOption('family', 'Family support', Icons.group_outlined),
      OnboardingOption('irregular', 'Irregular', Icons.schedule),
    ],
  ),
  OnboardingQuestion(
    id: 'saving_goal',
    title: 'What is the next thing you are saving for?',
    helper: "We'll help you create a goal and save for it, step by step.",
    allowOther: true,
    options: [
      OnboardingOption('phone', 'Phone', Icons.smartphone),
      OnboardingOption('bike', 'Bike', Icons.two_wheeler),
      OnboardingOption('trip', 'Trip', Icons.flight_takeoff),
      OnboardingOption('exam', 'Exam or course fee', Icons.school_outlined),
      OnboardingOption('festival', 'Festival or gift', Icons.card_giftcard),
      OnboardingOption('none', 'Nothing specific', Icons.track_changes),
    ],
  ),
  OnboardingQuestion(
    id: 'savings_location',
    title: 'Where do your savings sit today?',
    helper: 'Helps us suggest the best way for you to invest and grow.',
    allowOther: true,
    options: [
      OnboardingOption('bank', 'Bank account', Icons.account_balance_outlined),
      OnboardingOption('cash', 'Cash at home', Icons.money_outlined),
      OnboardingOption('gold', 'Gold or committee / chit', Icons.workspace_premium_outlined),
      OnboardingOption('none', "Haven't started", Icons.spa_outlined),
    ],
  ),
];

/// Answer payload sent to the backend for the logged-in user.
class OnboardingAnswers {
  /// questionId -> list of selected option ids (single-select = 1 entry)
  final Map<String, List<String>> selections;

  /// questionId -> free text, only when the user picked "Other"
  final Map<String, String> otherTexts;

  const OnboardingAnswers(this.selections, this.otherTexts);

  Map<String, dynamic> toJson() => {
    'answers': selections.entries
        .map((e) => {
      'questionId': e.key,
      'optionIds': e.value,
      if (otherTexts[e.key] != null && otherTexts[e.key]!.isNotEmpty)
        'otherText': otherTexts[e.key],
    })
        .toList(),
  };
}

/// Called by the caller AFTER OTP verification succeeds and a JWT exists.
/// Wire this to your Dio/ApiClient — same pattern as recharge/wallet calls.
abstract class OnboardingRepository {
  Future<void> submit(OnboardingAnswers answers);
}

/// Simple in-memory holder so answers collected here (pre-auth) can be
/// picked up again once OTP verification succeeds and a JWT is available.
/// Framework-agnostic — works whether you use Provider/Riverpod/GetX/Bloc,
/// since it's just a plain singleton. Clear it after a successful submit
/// so a later logout/re-login doesn't resubmit stale answers.
class OnboardingAnswerCache {
  OnboardingAnswerCache._();
  static final instance = OnboardingAnswerCache._();

  OnboardingAnswers? pending;

  void store(OnboardingAnswers answers) => pending = answers;

  /// Call this right after login succeeds (e.g. in your AuthService/
  /// AuthViewModel, immediately after verifyOtp() returns).
  ///
  /// [isNewUser] comes straight from AuthResponse.isNewUser (verifyOtp's
  /// return value in AuthService.kt already has this). Onboarding answers
  /// are only ever submitted for a brand-new signup — an existing user
  /// logging in again (new device, reinstall, etc.) has their profile
  /// already, so any cached answers are discarded, not sent.
  Future<void> flushIfPending(OnboardingRepository repo, {required bool isNewUser}) async {
    final answers = pending;
    if (answers == null) return;

    if (!isNewUser) {
      pending = null; // existing user — discard, nothing to submit
      return;
    }

    try {
      await repo.submit(answers);
      pending = null; // clear only on success; retry next app-open otherwise
    } catch (_) {
      // Swallow here — don't block login on this. Caller can log/report.
      // pending stays set, so you can retry later (e.g. next home-screen load).
    }
  }
}

// ── Screen ──

class OnboardingQuestionsScreen extends StatefulWidget {
  /// Called with the collected answers once the user hits "Continue".
  /// No backend call happens inside this screen — caller decides what's
  /// next (phone entry) and submits later, post-login.
  final ValueChanged<OnboardingAnswers> onComplete;

  const OnboardingQuestionsScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<OnboardingQuestionsScreen> createState() => _OnboardingQuestionsScreenState();
}

class _OnboardingQuestionsScreenState extends State<OnboardingQuestionsScreen> {
  final _pageController = PageController();
  int _page = 0;

  final Map<String, Set<String>> _selected = {};
  final Map<String, String> _otherText = {};
  final Map<String, TextEditingController> _otherControllers = {};

  static const _otherId = '_other';

  // Confetti now lives on the summary page itself (director's change:
  // the separate "SmartSave eligibility" page is gone; the celebration
  // fires the moment the user lands on "Your YouPi Financial Profile"
  // instead). Fires once, only for an eligible profile.
  bool _showConfetti = false;
  bool _celebrationFired = false;

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _otherControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isSummary => _page == _questions.length;

  void _toggle(OnboardingQuestion q, String optionId) {
    setState(() {
      final set = _selected.putIfAbsent(q.id, () => <String>{});
      if (q.multiSelect) {
        set.contains(optionId) ? set.remove(optionId) : set.add(optionId);
      } else {
        set
          ..clear()
          ..add(optionId);
      }
    });
  }

  void _next() {
    if (_page < _questions.length) {
      // BUG FIX: confetti used to trigger only from PageView's
      // onPageChanged callback, which fires once the nextPage() scroll
      // animation crosses the page boundary. That's timing-dependent --
      // if the callback doesn't land cleanly (fast taps, a rebuild mid
      // animation, etc.) the celebration silently never fires even
      // though the user genuinely selected answers. Firing it here,
      // synchronously the moment we know we're moving from the last
      // question into the summary, removes that dependency entirely.
      final goingToSummary = _page == _questions.length - 1;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      if (goingToSummary) {
        _maybeFireCelebration();
      }
    }
  }

  void _maybeFireCelebration() {
    if (_celebrationFired) return;
    final eligible = _selected.values.any((v) => v.isNotEmpty);
    if (eligible) {
      _celebrationFired = true;
      setState(() => _showConfetti = true);
    }
  }

  void _back() {
    if (_page > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _finish() {
    final selections = <String, List<String>>{};
    _selected.forEach((k, v) {
      if (v.isNotEmpty) selections[k] = v.toList();
    });
    widget.onComplete(OnboardingAnswers(selections, Map.of(_otherText)));
  }

  void _onPageChanged(int i) {
    setState(() => _page = i);
    // Kept as a backup path (belt-and-suspenders): if this DOES fire
    // correctly, _maybeFireCelebration()'s own _celebrationFired guard
    // makes it a harmless no-op when _next() already handled it.
    if (i == _questions.length) {
      _maybeFireCelebration();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _Header(
                  page: _page,
                  total: _questions.length,
                  isSummary: _isSummary,
                  onBack: _back,
                  onSkip: _isSummary ? null : _next,
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: _onPageChanged,
                    itemCount: _questions.length + 1,
                    itemBuilder: (context, i) {
                      if (i == _questions.length) {
                        return _SummaryPage(
                          selected: _selected,
                          otherText: _otherText,
                          onContinue: _finish,
                        );
                      }
                      final q = _questions[i];
                      return _QuestionPage(
                        question: q,
                        selected: _selected[q.id] ?? const {},
                        otherController: q.allowOther
                            ? _otherControllers.putIfAbsent(
                            q.id, () => TextEditingController(text: _otherText[q.id]))
                            : null,
                        onToggle: (id) => _toggle(q, id),
                        onOtherChanged: (v) => _otherText[q.id] = v.trim(),
                        onContinue: _next,
                        canContinue: (_selected[q.id]?.isNotEmpty ?? false),
                        otherId: _otherId,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Full-screen overlay, bottom-left/bottom-right cannon burst.
          if (_showConfetti)
            Positioned.fill(
              child: ConfettiBurst(
                onFinished: () {
                  if (mounted) setState(() => _showConfetti = false);
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Header with progress arc ──

class _Header extends StatelessWidget {
  final int page;
  final int total;
  final bool isSummary;
  final VoidCallback onBack;
  final VoidCallback? onSkip;

  const _Header({
    required this.page,
    required this.total,
    required this.isSummary,
    required this.onBack,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final progress = isSummary ? 1.0 : (page + 1) / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: _text),
          ),
          const Spacer(),
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  backgroundColor: _divider,
                  valueColor: const AlwaysStoppedAnimation(_accent),
                ),
                Text(
                  isSummary ? '✓' : '${page + 1}/$total',
                  style: const TextStyle(
                      color: _text, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (onSkip != null)
            TextButton(
              onPressed: onSkip,
              child: const Text('Skip', style: TextStyle(color: _muted)),
            )
          else
            const SizedBox(width: 64),
        ],
      ),
    );
  }
}

// ── Question page ──

class _QuestionPage extends StatelessWidget {
  final OnboardingQuestion question;
  final Set<String> selected;
  final TextEditingController? otherController;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onOtherChanged;
  final VoidCallback onContinue;
  final bool canContinue;
  final String otherId;

  const _QuestionPage({
    required this.question,
    required this.selected,
    required this.otherController,
    required this.onToggle,
    required this.onOtherChanged,
    required this.onContinue,
    required this.canContinue,
    required this.otherId,
  });

  @override
  Widget build(BuildContext context) {
    final showOtherField = question.allowOther && selected.contains(otherId);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          question.title,
          style: const TextStyle(
              color: _text, fontSize: 22, fontWeight: FontWeight.w700, height: 1.3),
        ),
        if (question.multiSelect)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Select all that apply',
                style: TextStyle(color: _muted, fontSize: 13)),
          ),
        const SizedBox(height: 20),
        for (final opt in question.options) ...[
          _OptionTile(
            label: opt.label,
            icon: opt.icon,
            selected: selected.contains(opt.id),
            multi: question.multiSelect,
            onTap: () => onToggle(opt.id),
          ),
          const SizedBox(height: 10),
        ],
        if (question.allowOther) ...[
          _OptionTile(
            label: 'Other',
            icon: Icons.edit_outlined,
            selected: selected.contains(otherId),
            multi: question.multiSelect,
            onTap: () => onToggle(otherId),
          ),
          if (showOtherField) ...[
            const SizedBox(height: 10),
            TextField(
              controller: otherController,
              onChanged: onOtherChanged,
              style: const TextStyle(color: _text),
              cursorColor: _accent,
              decoration: InputDecoration(
                hintText: 'Type your answer…',
                hintStyle: const TextStyle(color: _muted),
                filled: true,
                fillColor: _card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _accent, width: 1.5),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card.withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.lightbulb_outline, color: _accent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(question.helper,
                    style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.4)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: canContinue ? onContinue : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              disabledBackgroundColor: _card,
              foregroundColor: _accentDark,
              disabledForegroundColor: _muted,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text('Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.multi,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? _cardSelected : _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? _accent : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: selected ? _accent.withOpacity(0.15) : _divider.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 19, color: selected ? _accent : _muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: _text,
                          fontSize: 15,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                ),
                Icon(
                  multi
                      ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
                      : (selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
                  color: selected ? _accent : _muted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Summary page ──

class _SummaryPage extends StatelessWidget {
  final Map<String, Set<String>> selected;
  final Map<String, String> otherText;
  final VoidCallback onContinue;

  const _SummaryPage({
    required this.selected,
    required this.otherText,
    required this.onContinue,
  });

  String _labelsFor(OnboardingQuestion q) {
    final ids = selected[q.id] ?? const {};
    if (ids.isEmpty) return 'Skipped';
    final labels = <String>[];
    for (final id in ids) {
      if (id == '_other') {
        final t = otherText[q.id];
        labels.add((t == null || t.isEmpty) ? 'Other' : t);
      } else {
        labels.add(q.options.firstWhere((o) => o.id == id).label);
      }
    }
    return labels.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Text('Your YouPi\nFinancial Profile 👋',
            style: TextStyle(
                color: _text, fontSize: 26, fontWeight: FontWeight.w700, height: 1.25)),
        const SizedBox(height: 6),
        const Text("Here's what we understood about you.",
            style: TextStyle(color: _muted, fontSize: 13.5)),
        const SizedBox(height: 20),
        for (final q in _questions) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q.title,
                    style: const TextStyle(color: _muted, fontSize: 12)),
                const SizedBox(height: 4),
                Text(_labelsFor(q),
                    style: const TextStyle(
                        color: _text, fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: onContinue,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: _accentDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text('Continue  →',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text('🔒  Your data is encrypted and never shared.',
              style: TextStyle(color: _muted, fontSize: 12)),
        ),
      ],
    );
  }
}