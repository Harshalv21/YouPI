import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../data/repositories/invest_repository.dart';

/// Augmont Digital Gold FAQs -- a proper Help Center, not a static list:
/// search bar with live filtering, popular-topic chips, and questions
/// grouped by category. Content is fetched live from
/// GET /v1/gold/content/faqs (a JSON array of {"question", "answer",
/// "category"} objects -- see GoldContentEntity in InvestService.kt),
/// starting from the bundled list below as the initial paint and
/// silently upgrading on a successful fetch+parse -- falls back to the
/// bundled list with no visible error if the fetch fails.
class AugmontFaqScreen extends StatefulWidget {
  const AugmontFaqScreen({super.key});

  @override
  State<AugmontFaqScreen> createState() => _AugmontFaqScreenState();
}

typedef _Faq = (String question, String answer, String category);

class _AugmontFaqScreenState extends State<AugmontFaqScreen> {
  final InvestRepository _repo = InvestRepository();
  final _searchController = TextEditingController();
  List<_Faq> _faqs = _fallbackFaqs;
  String _query = '';
  String? _activeCategory;

  static const _categoryOrder = ['Buying Gold', 'Selling Gold', 'Payments', 'Orders'];

  // NOTE: the four Payments FAQs below (refund/payment-failure/purchase-
  // failure) state general, commonly-true fintech behaviour (funds
  // aren't lost, gateway-level reversal, standard timelines) but haven't
  // been signed off by Augmont or reviewed against YouPI's own actual
  // failure-handling code path. Flagging for a support/product review
  // pass before this ships -- same caution as the Refund Policy
  // placeholder screen.
  static const _fallbackFaqs = <_Faq>[
    (
    'What is Digital Gold?',
    'Digital Gold lets you buy physical bullion (gold/silver bars) for '
        'as low as Re. 1 with fully online access. You can request delivery '
        'of the gold/silver you\'ve purchased as coins, bars, or jewellery '
        'to your doorstep, and sell it back at any time.',
    'Buying Gold',
    ),
    (
    'What is the purity of the gold?',
    'Augmont offers 24K 999 (99.9% pure) gold, through its online '
        'platform, along with 24K 999 silver.',
    'Buying Gold',
    ),
    (
    'Why buy Digital Gold via Augmont?',
    'Simple, mobile-number-only account opening. No brokerage, storage, '
        'or insurance charges. Wholesale market pricing. You can sell back '
        'to Augmont at low spreads, and request doorstep delivery anytime.',
    'Buying Gold',
    ),
    (
    'How does Augmont ensure a fair price?',
    'Buy and Sell prices are quoted directly from wholesale spot market '
        'prices, so the benefit of wholesale pricing is passed on to you.',
    'Buying Gold',
    ),
    (
    'Is GST included in the price shown?',
    'Prices shown are exclusive of GST and other applicable taxes. GST '
        'is added at the final checkout step.',
    'Buying Gold',
    ),
    (
    'Why is there a difference between Buy and Sell price?',
    'The spread reflects price volatility, supply, and market '
        'conditions. GST applies on the buy price but not the sell price, '
        'and other charges (payment gateway, trustee, etc.) also '
        'contribute to the difference.',
    'Buying Gold',
    ),
    (
    'What is the minimum order quantity?',
    'You can buy gold or silver for as low as Re. 1, up to four '
        'decimal grams.',
    'Buying Gold',
    ),
    (
    'How are the grams I own calculated?',
    'The grams you own are calculated by dividing the amount paid '
        '(net of GST) by the gold rate, rounded DOWN to 4 decimal places '
        '-- e.g. .00054 g rounds down to .0005 g. This is Augmont\'s '
        'own disclosed method, printed on every tax invoice.',
    'Buying Gold',
    ),
    (
    'What happens when I sell my gold/silver?',
    'Sale proceeds are credited to your confirmed bank account, '
        'typically within one to two working days.',
    'Selling Gold',
    ),
    (
    'Can an order be cancelled?',
    'No -- once an order is successfully placed, it cannot be '
        'cancelled.',
    'Selling Gold',
    ),
    (
    'How does refund work?',
    'If money is deducted from your account for a Digital Gold order '
        'that didn\'t go through successfully, it\'s not lost -- it either '
        'never actually leaves your bank/wallet (a failed payment is not '
        'captured), or it\'s automatically reversed back to your original '
        'payment method.',
    'Payments',
    ),
    (
    'When will my refund be processed?',
    'Most payment-gateway-level reversals complete within 5-7 working '
        'days, depending on your bank. You\'ll see the amount back in your '
        'original payment method -- no separate refund request is usually '
        'needed for a failed transaction.',
    'Payments',
    ),
    (
    'What happens if payment fails?',
    'If your payment fails before it\'s captured, no gold order is '
        'created and no amount is deducted. If your bank shows a deduction '
        'for a failed payment, that amount is auto-reversed by your bank '
        'or payment gateway.',
    'Payments',
    ),
    (
    'What happens if my gold purchase fails?',
    'If payment was captured but the gold purchase itself couldn\'t be '
        'completed on Augmont\'s side, the amount is reversed back to your '
        'original payment method or credited to your YouPI wallet.',
    'Payments',
    ),
    (
    'Do I need to complete KYC?',
    'Yes -- KYC is a statutory requirement for buying on the Augmont '
        'platform. You may be prompted for PAN details once your buying '
        'crosses a certain threshold.',
    'Orders',
    ),
    (
    'Where is the physical gold/silver stored?',
    'It\'s stored securely in Sequel\'s vault -- the same vaulting '
        'service used by several banks and Gold-ETF Asset Management '
        'Companies in India -- and is covered by insurance.',
    'Orders',
    ),
    (
    'Who is the Independent Trustee?',
    'Valgo Finsec Services Private Limited (formerly Valmet Securities '
        'Services Private Limited), part of the Sequel group, acts as the '
        'Independent Trustee with first and exclusive charge over the '
        'bullion you purchase, protecting your interests.',
    'Orders',
    ),
    (
    'Can I request physical delivery?',
    'Yes -- you can request delivery of your gold/silver as coins, '
        'bars, or jewellery to your doorstep, by choosing from the '
        'available catalogue and paying a nominal making and delivery fee. '
        'Delivery typically takes up to 10 working days.',
    'Orders',
    ),
    (
    'Who do I contact for queries?',
    'Write to support@augmont.com, or call/WhatsApp +91 9090906867. '
        'Customer service hours: 10:00 am - 7:00 pm, Monday to Saturday '
        '(excluding public holidays).',
    'Orders',
    ),
    (
    'What if there\'s a dispute with my order?',
    'Once your gold or silver is delivered, Augmont\'s responsibility '
        'for that order ceases. Any disputes are subject to Mumbai '
        'jurisdiction, per the terms printed on every Augmont tax invoice.',
    'Orders',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    try {
      final raw = await _repo.getGoldContent('faqs');
      final decoded = jsonDecode(raw) as List;
      final parsed = decoded
          .map((e) => (
      e['question'] as String,
      e['answer'] as String,
      (e['category'] as String?) ?? 'Orders',
      ))
          .toList();
      if (mounted && parsed.isNotEmpty) {
        setState(() => _faqs = parsed);
      }
    } catch (_) {
      // Malformed JSON, missing "category" field, or network failure --
      // keep the bundled fallback, no visible error for a read-only page.
    }
  }

  List<_Faq> get _searchResults {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _faqs.where((f) =>
    f.$1.toLowerCase().contains(q) || f.$2.toLowerCase().contains(q)).toList();
  }

  Map<String, List<_Faq>> get _grouped {
    final source = _activeCategory == null
        ? _faqs
        : _faqs.where((f) => f.$3 == _activeCategory).toList();
    final map = <String, List<_Faq>>{};
    for (final cat in _categoryOrder) {
      final items = source.where((f) => f.$3 == cat).toList();
      if (items.isNotEmpty) map[cat] = items;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text('Frequently Asked Questions', style: AppTextStyles.headlineMedium),
        backgroundColor: AppColors.backgroundPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        children: [
          Text('How can we help?', style: AppTextStyles.headlineSmall),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.backgroundCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: AppTextStyles.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Search questions...',
                hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
                suffixIcon: isSearching
                    ? IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          if (!isSearching) ...[
            const SizedBox(height: 20),
            Text('Popular Topics', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final cat in _categoryOrder)
                GestureDetector(
                  onTap: () => setState(() => _activeCategory = _activeCategory == cat ? null : cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _activeCategory == cat ? AppColors.primary : AppColors.backgroundCard,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _activeCategory == cat ? AppColors.primary : AppColors.divider),
                    ),
                    child: Text(cat,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: _activeCategory == cat ? AppColors.backgroundPrimary : AppColors.textPrimary,
                          fontWeight: _activeCategory == cat ? FontWeight.bold : FontWeight.normal,
                        )),
                  ),
                ),
            ]),
          ],

          const SizedBox(height: 20),

          if (isSearching)
            if (_searchResults.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('No results for "$_query".',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
              )
            else
              for (final faq in _searchResults) _FaqTile(faq: faq)
          else
            for (final entry in _grouped.entries) ...[
              Text(entry.key, style: AppTextStyles.labelLarge),
              const SizedBox(height: 8),
              for (final faq in entry.value) _FaqTile(faq: faq),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final _Faq faq;
  const _FaqTile({required this.faq});

  @override
  Widget build(BuildContext context) {
    final (question, answer, _) = faq;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
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
      ),
    );
  }
}