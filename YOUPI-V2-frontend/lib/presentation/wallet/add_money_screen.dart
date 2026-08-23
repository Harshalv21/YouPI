import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/services/razorpay_service.dart';
import '../../core/widgets/youpi_button.dart';
import '../../data/repositories/wallet_repository.dart';
import '../invest/invest_viewmodel.dart' show WalletViewModel;

class AddMoneyScreen extends StatefulWidget {
  const AddMoneyScreen({super.key});
  @override
  State<AddMoneyScreen> createState() => _AddMoneyScreenState();
}

class _AddMoneyScreenState extends State<AddMoneyScreen> {
  final _walletRepo = WalletRepository();
  final _razorpayService = RazorpayService();
  final _amountController = TextEditingController();

  bool _isLoading = false;
  bool _isPolling = false;
  String? _error;

  static const _quickAmounts = [500.0, 1000.0, 2000.0, 5000.0];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double? get _enteredAmount => double.tryParse(_amountController.text.trim());

  // ← CHANGED: ab ye REPLACE nahi karta, current amount mein ADD karta hai.
  // ₹500 do baar tap kare to ₹1000 ban jaata hai, teesri baar ₹1500 -- taaki
  // koi bhi combination jaldi bana sake (jaise ₹500 + ₹2000 = ₹2500) bina
  // manually type kiye.
  void _addQuickAmount(double amount) {
    final current = _enteredAmount ?? 0;
    setState(() {
      _amountController.text = (current + amount).toStringAsFixed(0);
      _error = null;
    });
  }

  void _clearAmount() {
    setState(() {
      _amountController.clear();
      _error = null;
    });
  }

  Future<void> _addMoney() async {
    final amount = _enteredAmount;
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Please enter a valid amount.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // ── Step 1: create the order on the backend ──
      final order = await _walletRepo.createTopupOrder(amount);

      if (order.razorpayKeyId == null || order.razorpayKeyId!.isEmpty || order.orderId.isEmpty) {
        setState(() => _error = 'Could not start payment. Please try again.');
        return;
      }

      setState(() => _isLoading = false);

      // ── Step 2: open Razorpay checkout ──
      final rzResult = await _razorpayService.open(
        orderId: order.orderId,
        keyId: order.razorpayKeyId!,
        amountPaise: order.amountPaise,
        description: 'Wallet top-up',
      );

      if (rzResult.status == RazorpayResultStatus.failure) {
        setState(() => _error = rzResult.errorMessage ?? 'Payment failed. Please try again.');
        return;
      }
      if (rzResult.status == RazorpayResultStatus.cancelled) {
        // user backed out -- not an error, just stop quietly
        return;
      }

      // ── Step 3: poll backend to confirm the wallet was actually credited ──
      // Razorpay's checkout success callback is not confirmation -- same
      // contract as the recharge flow. Must wait for the webhook to land
      // server-side.
      setState(() => _isPolling = true);
      final confirmed = await _pollTopupStatus(order.orderId);

      if (!mounted) return;

      if (confirmed) {
        // Refresh wallet balance so it's up to date the moment we pop back.
        await context.read<WalletViewModel>().loadWallet();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Money added successfully!'),
          backgroundColor: AppColors.success,
        ));
        context.pop();
      } else {
        setState(() {
          _error = 'Payment received but confirmation is taking longer than usual. '
              'Check your wallet balance in a few minutes.';
        });
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPolling = false;
        });
      }
    }
  }

  /// Mirrors RechargeViewModel._pollOrderStatus() -- same interval/attempt
  /// budget, same "transient network hiccup, keep trying" behaviour.
  Future<bool> _pollTopupStatus(String orderId) async {
    const maxAttempts = 25;
    const interval = Duration(seconds: 2);
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future.delayed(interval);
      try {
        final status = await _walletRepo.getTopupOrderStatus(orderId);
        if (status.isCaptured) return true;
        if (status.isFailed) return false;
      } catch (_) {
        // transient network hiccup while polling -- don't abort early
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isLoading || _isPolling;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Add Money'), backgroundColor: AppColors.backgroundPrimary),
      // ← Removed the LayoutBuilder/IntrinsicHeight/Spacer combo -- that was
      // forcing the column to stretch to full screen height, which is what
      // created the big empty gap between the quick-amount chips and the
      // button. Plain scrollable column now; the button sits right after
      // the content instead of being pinned to the bottom of an
      // artificially-stretched column.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Enter Amount', style: AppTextStyles.displaySmall),
            const SizedBox(height: 16),

            // ← Amount now sits in a rounded card (matches the rest of the
            // app's card language) instead of a bare TextField with a
            // green underline.
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: AppColors.backgroundCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _amountController,
                enabled: !busy,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                style: AppTextStyles.amountLarge,
                textAlign: TextAlign.center,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  hintText: '0',
                  border: InputBorder.none,
                  isCollapsed: true,
                  prefixStyle: AppTextStyles.amountLarge.copyWith(color: AppColors.primary),
                  hintStyle: AppTextStyles.amountLarge.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text('Quick add', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            // ← 2x2 grid instead of a full-width stacked list -- these are
            // shortcuts, not navigation items, so a compact grid reads
            // better and leaves room to scan all four at once.
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.6,
              children: _quickAmounts.map((a) => OutlinedButton(
                onPressed: busy ? null : () => _addQuickAmount(a),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('+₹${a.toStringAsFixed(0)}',
                    style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primary, fontWeight: FontWeight.w600)),
              )).toList(),
            ),

            if (_enteredAmount != null && _enteredAmount! > 0) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : _clearAmount,
                  child: Text('Clear',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                ),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
            ],

            const SizedBox(height: 24),
            if (_isPolling) ...[
              const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              const SizedBox(height: 12),
              Center(
                child: Text('Confirming payment...', style: AppTextStyles.bodyMedium),
              ),
              const SizedBox(height: 20),
            ],
            YoupiButton(
              label: 'Add Money',
              isLoading: _isLoading,
              onPressed: busy ? null : _addMoney,
            ),
          ],
        ),
      ),
    );
  }
}