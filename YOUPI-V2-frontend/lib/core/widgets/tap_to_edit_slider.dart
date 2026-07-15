import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// A slider paired with a tappable value display. Tapping the value opens
/// the device's native number keypad (via a plain numeric TextField in a
/// dialog) so the user can type an exact figure instead of dragging --
/// the slider then jumps to match. Both interaction methods stay available
/// at all times, as requested: drag OR type, either always works.
///
/// Used for both money amounts (FD deposit, Gold buy amount) and plain
/// integer values (FD tenure in months) via [isInteger] + [displayFormatter].
class TapToEditSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String Function(double value) displayFormatter;
  final String dialogTitle;
  final String dialogHint;
  final bool isInteger;
  final Color? activeColor;

  const TapToEditSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.displayFormatter,
    required this.dialogTitle,
    this.dialogHint = 'Enter amount',
    this.isInteger = false,
    this.activeColor,
  });

  Future<void> _openEditDialog(BuildContext context) async {
    final controller = TextEditingController(
      text: isInteger ? value.round().toString() : value.toStringAsFixed(0),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: Text(dialogTitle, style: AppTextStyles.headlineSmall),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: AppTextStyles.amountMedium,
          decoration: InputDecoration(
            hintText: dialogHint,
            filled: true,
            fillColor: AppColors.backgroundSurface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppTextStyles.tealLink.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text);
              Navigator.pop(ctx, parsed);
            },
            child: Text('Confirm', style: AppTextStyles.tealLink),
          ),
        ],
      ),
    );

    // The dialog is closed by this point in every path (Cancel, Confirm, or
    // dismissed by tapping outside) -- safe to dispose here rather than
    // leaving the controller to be garbage-collected only "eventually".
    controller.dispose();

    if (result != null) {
      // Clamp to the slider's valid range -- a typed value outside min/max
      // would otherwise desync the slider or crash it.
      final clamped = result.clamp(min, max);
      final finalValue = isInteger ? clamped.roundToDouble() : clamped;

      // Defer the actual state change (which triggers a full Provider
      // rebuild via notifyListeners()) to the next frame, AFTER this
      // dialog's pop transition has fully settled. Calling onChanged
      // synchronously right after Navigator.pop() can race with the
      // dialog route still being torn down, which is what was throwing
      // "'_dependents.isEmpty': is not true" -- a Flutter Element still
      // being deactivated at the exact moment the Provider rebuild tore
      // out its ancestor subtree.
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(finalValue));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => _openEditDialog(context),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(displayFormatter(value), style: AppTextStyles.headlineSmall),
              const SizedBox(width: 6),
              const Icon(Icons.edit_rounded, size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: activeColor ?? AppColors.primary,
          inactiveColor: AppColors.divider,
          onChanged: onChanged,
        ),
      ],
    );
  }
}