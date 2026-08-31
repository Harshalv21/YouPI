import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';

/// Augmont Digital Gold FAQs, shown on the purchase flow per Augmont's
/// marketing checklist ("Include: About Us, FAQs, and Terms & Conditions
/// -- also on the page where customers will be purchasing Digital Gold").
/// Curated from Augmont's official FAQ document -- content unchanged,
/// only reformatted into question/answer pairs for the accordion UI.
class AugmontFaqScreen extends StatelessWidget {
  const AugmontFaqScreen({super.key});

  static const _faqs = [
    (
    'What is Digital Gold?',
    'Digital Gold lets you buy physical bullion (gold/silver bars) for '
        'as low as Re. 1 with fully online access. You can request delivery '
        'of the gold/silver you\'ve purchased as coins, bars, or jewellery '
        'to your doorstep, and sell it back at any time.',
    ),
    (
    'What is the purity of the gold?',
    'Augmont offers 24K 999 (99.9% pure) gold, through its online '
        'platform, along with 24K 999 silver.',
    ),
    (
    'Why buy Digital Gold via Augmont?',
    'Simple, mobile-number-only account opening. No brokerage, storage, '
        'or insurance charges. Wholesale market pricing. You can sell back '
        'to Augmont at low spreads, and request doorstep delivery anytime.',
    ),
    (
    'How does Augmont ensure a fair price?',
    'Buy and Sell prices are quoted directly from wholesale spot market '
        'prices, so the benefit of wholesale pricing is passed on to you.',
    ),
    (
    'Is GST included in the price shown?',
    'Prices shown are exclusive of GST and other applicable taxes. GST '
        'is added at the final checkout step.',
    ),
    (
    'Why is there a difference between Buy and Sell price?',
    'The spread reflects price volatility, supply, and market '
        'conditions. GST applies on the buy price but not the sell price, '
        'and other charges (payment gateway, trustee, etc.) also '
        'contribute to the difference.',
    ),
    (
    'What happens when I sell my gold/silver?',
    'Sale proceeds are credited to your confirmed bank account, '
        'typically within three working days.',
    ),
    (
    'What is the minimum order quantity?',
    'You can buy gold or silver for as low as Re. 1, up to four '
        'decimal grams.',
    ),
    (
    'Do I need to complete KYC?',
    'Yes -- KYC is a statutory requirement for buying on the Augmont '
        'platform. You may be prompted for PAN details once your buying '
        'crosses a certain threshold.',
    ),
    (
    'Where is the physical gold/silver stored?',
    'It\'s stored securely in Sequel\'s vault -- the same vaulting '
        'service used by several banks and Gold-ETF Asset Management '
        'Companies in India -- and is covered by insurance.',
    ),
    (
    'Who is the Independent Trustee?',
    'Valgo Finsec Services Private Limited (formerly Valmet Securities '
        'Services Private Limited), part of the Sequel group, acts as the '
        'Independent Trustee with first and exclusive charge over the '
        'bullion you purchase, protecting your interests.',
    ),
    (
    'Can I request physical delivery?',
    'Yes -- you can request delivery of your gold/silver as coins, '
        'bars, or jewellery to your doorstep, by choosing from the '
        'available catalogue and paying a nominal making and delivery fee. '
        'Delivery typically takes up to 10 working days.',
    ),
    (
    'Can an order be cancelled?',
    'No -- once an order is successfully placed, it cannot be '
        'cancelled.',
    ),
    (
    'Who do I contact for queries?',
    'Write to support@augmont.com, or call/WhatsApp +91 9090906867. '
        'Customer service hours: 10:00 am - 7:00 pm, Monday to Saturday '
        '(excluding public holidays).',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text('Digital Gold FAQs', style: AppTextStyles.headlineMedium),
        backgroundColor: AppColors.backgroundPrimary,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        itemCount: _faqs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final (question, answer) = _faqs[i];
          return Container(
            decoration: BoxDecoration(
              color: AppColors.backgroundCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text(question, style: AppTextStyles.labelLarge),
                iconColor: AppColors.primary,
                collapsedIconColor: AppColors.textSecondary,
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    answer,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}