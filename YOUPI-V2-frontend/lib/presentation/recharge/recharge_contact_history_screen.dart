// lib/presentation/recharge/recharge_contact_history_screen.dart
//
// GPay-style "tap a contact -> see their recharge history + browse plans"
// screen. One continuous scroll (chat history on top, search + category
// tabs + plan list below, like GPay's bill-pay contact screen) instead of
// two separate boxed-off halves.
//
// All data is real (RechargeRepository / RechargeViewModel), no mocks.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../data/models/recharge_plan_model.dart';
import '../../data/repositories/recharge_repository.dart';
import 'recharge_history_screen.dart' show RechargeRecord, RechargeStatus, StatusBadge, formatShortDate;
import 'recharge_viewmodel.dart';

class RechargeContactHistoryScreen extends StatefulWidget {
  final String mobileNumber;
  final String? contactName;

  const RechargeContactHistoryScreen({
    super.key,
    required this.mobileNumber,
    this.contactName,
  });

  @override
  State<RechargeContactHistoryScreen> createState() => _RechargeContactHistoryScreenState();
}

class _RechargeContactHistoryScreenState extends State<RechargeContactHistoryScreen> {
  final RechargeRepository _repo = RechargeRepository();
  final _searchCtrl = TextEditingController();
  // Lets the fixed header (handle + search + tabs, which sits OUTSIDE the
  // scrollable plan list) drag the sheet too -- by default
  // DraggableScrollableSheet only recognizes drag gestures coming through
  // its scrollable child, so grabbing the header did nothing before this.
  final _sheetController = DraggableScrollableController();
  static const double _sheetMinSize = 0.46;
  static const double _sheetMaxSize = 0.92;

  bool _loadingHistory = true;
  bool _loadingPlans = true;
  bool _payingRecord = false; // guards double-taps on Repeat recharge
  List<RechargeRecord> _history = [];
  List<RechargePlanModel> _plans = [];
  String _operator = '';
  String _circle = '';
  String _searchQuery = '';
  String _activeTab = '';
  String? _payError;
  // BUG FIX: previously the catch block below just flipped _loadingPlans
  // to false and swallowed the exception entirely -- a failed plans load
  // (rate limit, timeout, mPlan's "not authorize" issue, anything) looked
  // IDENTICAL to a genuine "this operator has no plans" empty state, with
  // no way to tell which one happened and no way to retry without leaving
  // the screen. This is very likely what's behind the "load plans for a
  // second contact and nothing shows" report -- the second call may be
  // failing (e.g. a backend/HLR rate limit on rapid repeat lookups) and
  // we were never showing that failure.
  String? _plansError;

  // Real categories from mPlan (via backend's PlanResponse.category, which
  // Flutter's RechargePlanModel already carries in `.tier`) -- e.g.
  // "POPULAR", "TOPUP", "COMBO", "SPECIAL", whatever mPlan actually groups
  // this operator's plans under. No client-side guessing anymore. Falls
  // back to a single "All Plans" tab if plans haven't loaded yet or mPlan
  // sent no usable category for any of them.
  List<String> get _tabs {
    final categories = _plans.map((p) => p.tier).where((t) => t.isNotEmpty).toSet().toList();
    if (categories.isEmpty) return const ['All Plans'];
    categories.sort((a, b) {
      if (a == 'POPULAR') return -1;
      if (b == 'POPULAR') return 1;
      return a.compareTo(b);
    });
    return categories;
  }

  List<RechargePlanModel> get _visiblePlans {
    var list = _activeTab == 'All Plans' ? _plans : _plans.where((p) => p.tier == _activeTab).toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((p) =>
      p.name.toLowerCase().contains(q) ||
          p.price.toStringAsFixed(0).contains(q)).toList();
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  // Both calls fire together instead of one-after-another -- that
  // sequential await was the main reason the screen felt slow to open.
  Future<void> _load() async {
    setState(() {
      _loadingHistory = true;
      _loadingPlans = true;
    });
    await Future.wait([_loadHistory(), _loadPlans()]);
  }

  Future<void> _loadHistory() async {
    try {
      final all = await _repo.getAllRechargeHistory();
      final mine = all.where((r) => r.mobileNumber == widget.mobileNumber).toList();
      mine.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (!mounted) return;
      setState(() {
        _history = mine;
        _loadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
    }
  }

  // Auto-detected operator (mPlan HLR lookup) can be wrong for a recently
  // number-ported (MNP) SIM -- the carrier's own HLR record updates almost
  // instantly on a port, but third-party lookup providers like mPlan can
  // lag behind by anywhere from minutes to days. This is a real, common
  // scenario for Indian telecom (not a bug we can "fix" upstream), so --
  // same as GPay/PhonePe/Paytm -- the user needs a manual override instead
  // of being stuck with whatever mPlan says.
  static const _operatorOptions = ['JIO', 'AIRTEL', 'VI', 'BSNL', 'MTNL'];

  void _showOperatorPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('Select operator', style: AppTextStyles.headlineSmall),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                _operator.isEmpty
                    ? 'We couldn\'t auto-detect this number\'s operator. Pick it manually to see plans.'
                    : 'We detected $_operator automatically. If this number was recently ported, pick the correct one below.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
            ),
            ..._operatorOptions.map((op) => ListTile(
              title: Text(op, style: AppTextStyles.bodyMedium),
              trailing: op == _operator.toUpperCase()
                  ? Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
                  : null,
              onTap: () {
                Navigator.of(sheetContext).pop();
                if (op != _operator.toUpperCase()) _changeOperator(op);
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _changeOperator(String newOperator) async {
    setState(() {
      _loadingPlans = true;
      _plansError = null;
    });
    try {
      final plans = await _repo.getPlans(operator: newOperator, circle: _circle);
      if (!mounted) return;
      setState(() {
        _operator = newOperator;
        _plans = plans;
        _loadingPlans = false;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Manual operator change failed for $newOperator/$_circle: $e');
      setState(() {
        _loadingPlans = false;
        _plansError = 'Please check your connection and try again.';
      });
    }
  }

  Future<void> _loadPlans() async {
    setState(() => _plansError = null);
    try {
      final detection = await _repo.detectOperator(widget.mobileNumber);
      final plans = await _repo.getPlans(
        operator: detection.operator.toUpperCase(),
        circle: detection.circle,
      );
      if (!mounted) return;
      setState(() {
        _operator = detection.operator;
        _circle = detection.circle;
        _plans = plans;
        _loadingPlans = false;
        if (_activeTab.isEmpty) {
          final categories = plans.map((p) => p.tier).where((t) => t.isNotEmpty).toSet();
          _activeTab = categories.contains('POPULAR')
              ? 'POPULAR'
              : (categories.isNotEmpty ? categories.first : 'All Plans');
        }
      });
    } catch (e) {
      if (!mounted) return;
      // The RAW error (rate limit / timeout / mPlan's "not authorize" / etc.)
      // is logged here for OUR debugging only -- during dev, run this with
      // `flutter run` (not a release build) and watch the console, or check
      // `adb logcat` on a release build, to see the real reason.
      //
      // It must NEVER be shown to the user directly -- no real fintech app
      // surfaces raw backend/vendor error strings (confusing, unprofessional,
      // and can leak implementation details like vendor names/internal error
      // codes). The UI always gets a short, generic, actionable message
      // instead, same as PhonePe/GPay/Paytm do for any plan/catalog load
      // failure.
      debugPrint('Plans load failed for ${widget.mobileNumber}: $e');
      setState(() {
        _loadingPlans = false;
        _plansError = 'Please check your connection and try again.';
      });
    }
  }

  // Tapping "Repeat recharge" pays immediately -- it does NOT navigate
  // away. Finds the matching plan (same price) from the already-loaded
  // plan list so createOrder() has the planId/validityDays it needs; if
  // that plan is no longer on sale, tells the user instead of guessing at
  // stale plan data.
  Future<void> _repeatRecharge(RechargeRecord record) async {
    if (_payingRecord) return;
    final match = _plans.where((p) => p.price == record.amount).toList();
    if (match.isEmpty) {
      setState(() {
        _payError = 'That exact plan isn\'t available anymore -- pick a fresh one below.';
      });
      return;
    }
    setState(() {
      _payingRecord = true;
      _payError = null;
    });
    final vm = context.read<RechargeViewModel>();
    // autoDetectOperator: false -- this screen already has the CORRECT,
    // already-detected operator/circle for this exact number (used in the
    // "Browse plans · OPERATOR CIRCLE" header above). Letting setMobile()
    // ALSO kick off its own background re-detection was the actual bug --
    // see setMobile()'s doc comment in recharge_viewmodel.dart for the
    // full race-condition explanation.
    vm.setMobile(widget.mobileNumber, autoDetectOperator: false);
    vm.setOperatorAndCircle(_operator, _circle);
    vm.selectPlan(match.first);
    final success = await vm.payAndConfirm();
    if (!mounted) return;
    setState(() => _payingRecord = false);
    if (success) {
      _loadHistory(); // refresh the feed so the new order appears
    } else {
      setState(() => _payError = vm.error ?? 'Payment did not complete.');
    }
  }

  void _selectPlan(RechargePlanModel plan) {
    final vm = context.read<RechargeViewModel>();
    // Same fix as _repeatRecharge() below -- this screen already has the
    // CORRECT, already-detected operator/circle for this number (used in
    // the "Browse plans · OPERATOR CIRCLE" header). Letting setMobile()
    // ALSO kick off its own redundant background re-detection here was
    // the same race-condition bug, just on the far more common path (this
    // is the NORMAL "tap a plan to recharge" flow, not just Repeat) --
    // see setMobile()'s doc comment in recharge_viewmodel.dart.
    vm.setMobile(widget.mobileNumber, autoDetectOperator: false);
    vm.setOperatorAndCircle(_operator, _circle);
    vm.selectPlan(plan);
    context.push('/plans/emi-select');
  }

  // Same on-device "clear" as the main Recharge History screen -- hides
  // these entries from view everywhere (this screen, Recent Recharges,
  // View All), never touches the backend records. See StorageService's
  // hidden-history-ids doc comment for why.
  Future<void> _confirmAndClearHistory() async {
    if (_history.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: Text('Clear history?', style: AppTextStyles.headlineSmall),
        content: Text(
          'This hides ${widget.contactName?.isNotEmpty == true ? widget.contactName : widget.mobileNumber}\'s '
              'recharge history from view. Your transaction records stay safe on our servers and aren\'t deleted.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Clear', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.hideFromHistory(_history.map((r) => r.id));
    if (!mounted) return;
    setState(() => _history = []);
  }

  // "POPULAR" / "FULLTT" -> "Popular" / "Fulltt" -- just a display nicety,
  // the raw value from mPlan (via plan.tier) is still what's compared
  // against when filtering.
  String _prettyTab(String raw) {
    if (raw == 'All Plans') return raw;
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.contactName?.isNotEmpty == true ? widget.contactName! : widget.mobileNumber;
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary.withOpacity(0.15),
              child: Text(
                title.isNotEmpty ? title[0].toUpperCase() : '#',
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('+91 ${widget.mobileNumber}', style: AppTextStyles.captionText),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!_loadingHistory && _history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Clear history',
              onPressed: _confirmAndClearHistory,
            ),
        ],
      ),
      // History feed sits as the page background; the plans panel is a
      // DraggableScrollableSheet docked to the bottom -- the user can drag
      // the WHOLE panel up/down (not just scroll the list inside it),
      // matching GPay's contact-bill screen where the sheet itself moves.
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: _buildHistorySection(),
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: _sheetMinSize,
            minChildSize: _sheetMinSize,
            maxChildSize: _sheetMaxSize,
            snap: true,
            builder: (context, sheetScrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.backgroundCard,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
                ),
                child: Column(
                  children: [
                    // The handle + search + tabs area sits OUTSIDE the
                    // scrollable list below, so DraggableScrollableSheet's
                    // built-in "drag the scrollable to resize" behaviour
                    // doesn't cover it on its own -- wrapped in a
                    // GestureDetector that drives the sheet controller
                    // directly, so grabbing anywhere up here (not just the
                    // plan list) moves the whole panel, like GPay.
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragUpdate: (details) {
                        final screenHeight = MediaQuery.of(context).size.height;
                        final delta = details.primaryDelta ?? 0;
                        final newSize = (_sheetController.size - delta / screenHeight)
                            .clamp(_sheetMinSize, _sheetMaxSize);
                        _sheetController.jumpTo(newSize);
                      },
                      onVerticalDragEnd: (details) {
                        // Snap to whichever end is closer instead of
                        // leaving the sheet stuck at an odd in-between
                        // height.
                        final mid = (_sheetMinSize + _sheetMaxSize) / 2;
                        _sheetController.animateTo(
                          _sheetController.size >= mid ? _sheetMaxSize : _sheetMinSize,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 6),
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.textSecondary.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          _buildSearchAndTabs(),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _loadingPlans
                          ? const Center(child: CircularProgressIndicator())
                          : _plansError != null
                          ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.wifi_off_rounded, color: AppColors.textSecondary, size: 32),
                              const SizedBox(height: 10),
                              Text('Couldn\'t load plans',
                                  style: AppTextStyles.labelLarge, textAlign: TextAlign.center),
                              const SizedBox(height: 4),
                              Text(_plansError!,
                                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () {
                                  setState(() => _loadingPlans = true);
                                  _loadPlans();
                                },
                                child: const Text('Retry'),
                              ),
                              // BUG FIX: previously, if operator
                              // auto-detection itself failed (some
                              // numbers' HLR lookups fail/timeout at
                              // mPlan), _operator stayed empty and the
                              // "Change operator" link -- which only
                              // showed inside `if (_operator.isNotEmpty)`
                              // below -- never appeared. The user was
                              // stuck retrying the same failing
                              // detection with no way to just pick their
                              // operator manually and move on.
                              TextButton(
                                onPressed: _showOperatorPicker,
                                child: const Text('Select operator manually'),
                              ),
                            ],
                          ),
                        ),
                      )
                          : _visiblePlans.isEmpty
                          ? Center(
                        child: Text('No plans found',
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                      )
                          : ListView.separated(
                        controller: sheetScrollController,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _visiblePlans.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _planTile(_visiblePlans[i]),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Browse plans', style: AppTextStyles.headlineSmall),
              if (_operator.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text('· ${_operator.toUpperCase()} $_circle',
                    style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _showOperatorPicker,
                  child: Text('Change',
                      style: AppTextStyles.captionText.copyWith(
                        color: AppColors.primary,
                        decoration: TextDecoration.underline,
                      )),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v),
            style: AppTextStyles.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              hintText: 'Search for a plan or enter amount',
              filled: true,
              fillColor: AppColors.backgroundPrimary,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final t = _tabs[i];
                final selected = t == _activeTab;
                return GestureDetector(
                  onTap: () => setState(() => _activeTab = t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: selected ? AppColors.primary : AppColors.textSecondary.withOpacity(0.2)),
                    ),
                    child: Text(
                      _prettyTab(t),
                      style: AppTextStyles.captionText.copyWith(
                        color: selected ? AppColors.primary : AppColors.textSecondary,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    if (_loadingHistory) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'No recharges yet for this number',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    String? lastDateLabel;
    final children = <Widget>[];
    for (final r in _history) {
      final label = formatShortDate(r.createdAt);
      if (label != lastDateLabel) {
        children.add(_dateDivider(label));
        lastDateLabel = label;
      }
      children.add(_historyBubble(r));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _dateDivider(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SizedBox(
        width: double.infinity,
        child: Text(label, textAlign: TextAlign.center, style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)),
      ),
    );
  }

  Widget _historyBubble(RechargeRecord r) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.backgroundCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('₹${r.amount.toStringAsFixed(0)} recharge', style: AppTextStyles.labelLarge),
                StatusBadge(status: r.status),
              ],
            ),
            const SizedBox(height: 6),
            if (r.planDescription.isNotEmpty)
              Text(r.planDescription, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            if (r.status == RechargeStatus.success)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _payingRecord ? null : () => _repeatRecharge(r),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _payingRecord
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Text('Repeat recharge',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              ),
            if (_payError != null) ...[
              const SizedBox(height: 6),
              Text(_payError!, style: AppTextStyles.captionText.copyWith(color: AppColors.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _planTile(RechargePlanModel plan) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _selectPlan(plan),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.backgroundCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.name, style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${plan.dataPerDay}/day • ${plan.validityDays} Days • ${plan.callsInfo}',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Text('₹${plan.price.toStringAsFixed(0)}',
                style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}