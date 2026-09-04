import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/youpi_button.dart';
import 'dth_viewmodel.dart';

class DthCustomerIdScreen extends StatefulWidget {
  const DthCustomerIdScreen({super.key});
  @override
  State<DthCustomerIdScreen> createState() => _DthCustomerIdScreenState();
}

class _DthCustomerIdScreenState extends State<DthCustomerIdScreen> {
  final _idCtrl = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _onConfirm(DthViewModel vm) async {
    final value = _idCtrl.text.trim();
    if (value.isEmpty) {
      setState(() => _localError = 'Enter your subscriber ID first');
      return;
    }
    setState(() => _localError = null);
    vm.setSubscriberNumber(value);

    final found = await vm.fetchCustomerInfo();
    if (!mounted) return;

    if (found) {
      context.push('/dth/amount');
    } else {
      setState(() {
        _localError = vm.customerInfoError ??
            'Could not verify this subscriber ID. Please check and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DthViewModel>(builder: (ctx, vm, _) {
      final operatorName = vm.selectedOperator?.displayName ?? 'DTH';
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
          title: Text(operatorName, style: AppTextStyles.headlineMedium),
          backgroundColor: AppColors.backgroundPrimary,
        ),
        body: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Subscriber ID', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _idCtrl,
                keyboardType: TextInputType.number,
                style: AppTextStyles.labelLarge,
                decoration: InputDecoration(
                  hintText: 'Enter subscriber ID',
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
              const SizedBox(height: 10),
              Text(
                'Press the Menu button on your remote and select My Account to find your subscriber ID.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              YoupiButton(
                label: vm.isFetchingCustomerInfo ? 'Checking...' : 'Confirm',
                onPressed: vm.isFetchingCustomerInfo ? null : () => _onConfirm(vm),
              ),
            ],
          ),
        ),
      );
    });
  }
}