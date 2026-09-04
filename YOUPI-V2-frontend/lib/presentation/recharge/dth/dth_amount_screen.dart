import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/youpi_button.dart';
import '../gold_coin_reward_screen.dart';
import 'dth_viewmodel.dart';

const List<double> _kQuickAmounts = [300, 500, 1000];

class DthAmountScreen extends StatefulWidget {
  const DthAmountScreen({super.key});
  @override
  State<DthAmountScreen> createState() => _DthAmountScreenState();
}

class _DthAmountScreenState extends State<DthAmountScreen> {
  final _amountCtrl = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  void _pickQuickAmount(double value) {
    _amountCtrl.text = value.toStringAsFixed(0);
    setState(() => _localError = null);
  }

  // Same 1%-of-amount math as mobile recharge's coin calculation
  // (EmiSelectionScreen._valueForAmount/_coinsForAmount) -- DTH has no
  // Rs.249 minimum, so this always applies, unlike mobile's threshold gate.
  double _valueForAmount(double rechargeAmount) => rechargeAmount * 0.01;
  int _coinsForAmount(double rechargeAmount) =>
      (_valueForAmount(rechargeAmount) / 0.10).round();

  Future<void> _onProceed(DthViewModel vm) async {
    final raw = _amountCtrl.text.trim();
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      setState(() => _localError = 'Enter a valid amount');
      return;
    }
    setState(() => _localError = null);
    vm.setAmount(parsed);

    final success = await vm.payAndConfirm();
    if (!mounted) return;

    if (success) {
      // DTH earns 1% cashback on every successful recharge regardless of
      // amount (no Rs.249 minimum like mobile) -- so this always shows
      // the gold coin reward, matching mobile's plan.price >= 249 branch.
      await showGoldCoinReward(
        context,
        parsed,
        onNavigateHome: () => context.go(
          '/dashboard/home',
          extra: {
            'justEarnedCoin': true,
            'earnedCoins': _coinsForAmount(parsed),
            'earnedValue': _valueForAmount(parsed),
          },
        ),
      );
    } else if (vm.stillProcessing) {
      context.go('/dashboard/home');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(vm.error ?? 'Payment received — confirming your recharge.'),
          backgroundColor: AppColors.backgroundCard,
        ),
      );
    } else if (vm.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vm.error!)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong confirming your recharge. Please check My Recharges.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DthViewModel>(builder: (ctx, vm, _) {
      final operatorName = vm.selectedOperator?.displayName ?? 'DTH';
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
          title: Text('Enter amount', style: AppTextStyles.headlineMedium),
          backgroundColor: AppColors.backgroundPrimary,
        ),
        body: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.tv_rounded, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(operatorName, style: AppTextStyles.labelLarge),
                      Text(vm.subscriberNumber, style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Amount', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                style: AppTextStyles.headlineSmall,
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  hintText: '0',
                  filled: true,
                  fillColor: AppColors.backgroundCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  errorText: _localError,
                ),
                onChanged: (_) {
                  if (_localError != null) setState(() => _localError = null);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: _kQuickAmounts
                    .map((amt) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: OutlinedButton(
                              onPressed: () => _pickQuickAmount(amt),
                              child: Text('₹${amt.toStringAsFixed(0)}'),
                            ),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 14),
              Text(
                "Bill amount isn't auto-fetched yet — enter it manually for now.",
                style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              YoupiButton(
                label: vm.isLoading || vm.paymentInProgress ? 'Processing...' : 'Proceed to pay',
                onPressed: (vm.isLoading || vm.paymentInProgress) ? null : () => _onProceed(vm),
              ),
            ],
          ),
        ),
      );
    });
  }
}