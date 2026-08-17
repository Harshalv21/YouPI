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

  void _selectQuickAmount(double amount) {
    setState(() {
      _amountController.text = amount.toStringAsFixed(0);
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimensions.paddingPage),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - (AppDimensions.paddingPage * 2),
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Enter Amount', style: AppTextStyles.displaySmall),
                    const SizedBox(height: 24),
                    TextField(
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
                        prefixStyle: AppTextStyles.amountLarge,
                        hintStyle: AppTextStyles.amountLarge.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                    const Divider(color: AppColors.primary, thickness: 2),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      children: _quickAmounts.map((a) => OutlinedButton(
                        onPressed: busy ? null : () => _selectQuickAmount(a),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary)),
                        child: Text('₹${a.toStringAsFixed(0)}'),
                      )).toList(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
                    ],
                    const Spacer(),
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
            ),
          );
        },
      ),
    );
  }
}