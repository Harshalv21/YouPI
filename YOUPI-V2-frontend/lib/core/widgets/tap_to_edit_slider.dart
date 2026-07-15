import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// A slider paired with a tappable value display. Tapping the value opens
/// the device's native number keypad (via a plain numeric TextField in a
/// dialog) so the user can type an exact figure instead of dragging --
/// the slider then jumps to match. Both interaction methods stay available
/// at all times: drag OR type, either always works.
///
/// Used for both money amounts (FD deposit, Gold buy amount) and plain
/// integer values (FD tenure in months) via [isInteger] + [displayFormatter].
class TapToEditSlider extends StatefulWidget {
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

  @override
  State<TapToEditSlider> createState() => _TapToEditSliderState();
}

class _TapToEditSliderState extends State<TapToEditSlider> {
  Future<void> _openEditDialog(BuildContext context) async {
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => _EditAmountDialog(
        initialValue: widget.isInteger
            ? widget.value.round().toString()
            : widget.value.toStringAsFixed(0),
        title: widget.dialogTitle,
        hint: widget.dialogHint,
      ),
    );

    // This widget can be gone by the time the dialog closes (user backed
    // out of the whole screen while the dialog was still up) -- guard
    // before touching state/callbacks any further.
    if (!mounted) return;

    if (result != null) {
      final clamped = result.clamp(widget.min, widget.max);
      final finalValue = widget.isInteger ? clamped.roundToDouble() : clamped;

      // Defer the actual state change (which triggers a full Provider
      // rebuild via notifyListeners()) to the next frame, after the
      // dialog's pop transition has fully settled.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(finalValue);
      });
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
              Text(widget.displayFormatter(widget.value), style: AppTextStyles.headlineSmall),
              const SizedBox(width: 6),
              const Icon(Icons.edit_rounded, size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
        Slider(
          value: widget.value.clamp(widget.min, widget.max),
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          activeColor: widget.activeColor ?? AppColors.primary,
          inactiveColor: AppColors.divider,
          onChanged: widget.onChanged,
        ),
      ],
    );
  }
}

/// Dialog content with its OWN TextEditingController, created in initState
/// and disposed in dispose() -- tied exactly to the dialog's own widget
/// lifecycle. This is what actually fixes the "TextEditingController used
/// after being disposed" / "_dependents.isEmpty" crash: the previous
/// version created the controller in the caller and manually disposed it
/// right after `await showDialog(...)` returned, which raced with
/// Flutter's own route-teardown timing for the dialog. Letting Flutter own
/// the controller's lifecycle via a proper StatefulWidget avoids that race
/// structurally instead of patching around it.
class _EditAmountDialog extends StatefulWidget {
  final String initialValue;
  final String title;
  final String hint;

  const _EditAmountDialog({
    required this.initialValue,
    required this.title,
    required this.hint,
  });

  @override
  State<_EditAmountDialog> createState() => _EditAmountDialogState();
}

class _EditAmountDialogState extends State<_EditAmountDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.backgroundCard,
      title: Text(widget.title, style: AppTextStyles.headlineSmall),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: AppTextStyles.amountMedium,
        decoration: InputDecoration(
          hintText: widget.hint,
          filled: true,
          fillColor: AppColors.backgroundSurface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: AppTextStyles.tealLink.copyWith(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () {
            final parsed = double.tryParse(_controller.text);
            Navigator.pop(context, parsed);
          },
          child: Text('Confirm', style: AppTextStyles.tealLink),
        ),
      ],
    );
  }
}