import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_text_styles.dart';

/// Augmont co-branding badge -- required by Augmont's marketing checklist:
/// "Partner branding to clearly show Augmont's name and logo" and
/// "'Powered by Augmont' should be on the page where customers are
/// purchasing the Digital Gold".
///
/// Wrapped in a white card on purpose: Augmont's logo (dark teal + gold)
/// has very low contrast directly on our dark app background. Augmont's
/// own placement mockup (Guidelines pack, "Darker App background" slides)
/// does the exact same thing -- a light pill behind the logo -- so this
/// matches their own spec rather than working around it.
class AugmontBadge extends StatelessWidget {
  final bool tappable;
  const AugmontBadge({super.key, this.tappable = true});

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Powered by',
            style: AppTextStyles.captionText.copyWith(
              color: Colors.black54,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 2),
          Image.asset('assets/images/augmont-logo.png', height: 16),
        ],
      ),
    );

    if (!tappable) return badge;

    return GestureDetector(
      onTap: () => context.push('/invest/gold/about-augmont'),
      child: badge,
    );
  }
}