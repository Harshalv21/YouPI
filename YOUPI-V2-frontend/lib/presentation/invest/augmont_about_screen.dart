import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';

/// Augmont's official "About Us" copy, shown on the digital gold purchase
/// flow per Augmont's marketing checklist ("Include: About Us, FAQs, and
/// Terms & Conditions -- also on the page where customers will be
/// purchasing Digital Gold"). Text is Augmont's own, unedited.
class AugmontAboutScreen extends StatelessWidget {
  const AugmontAboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text('About Augmont', style: AppTextStyles.headlineMedium),
        backgroundColor: AppColors.backgroundPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset('assets/images/augmont-logo.png', height: 40),
            const SizedBox(height: 24),
            Text(
              _aboutText,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

const _aboutText = r'''
ABOUT US

Augmont was incorporated in 2013 with the vision to provide a seamless, integrated offering to business and retail customers for anything related to gold. The idea was to leverage the power of technology combined with the strength of gold as an investment as well as a consumer good. Innovation is the bedrock of growth for Augmont. Whether it's innovation in processes, product design, or distribution, Augmont has been delivering more and efficiently to its customers.

AUGMONT GOLD FOR ALL

Augmont "GOLD FOR ALL" is a revolutionary Goldtech ecosystem to make Gold accessible, affordable, useful, and manageable for all phases of a customer’s life. It is the one-stop destination for gold and silver. Augmont has derived its name from the combination of the words Au and Ag, the chemical symbols for 'Gold' and 'Silver' respectively. The word “Augment” means to increase or to make something greater by adding to it.

Augmont Gold For All, products aims to touch every aspect of a customer’s life. Gold should be seen as a life-enabling companion for life. To this Augmont’s constant effort is to make bigger and more revolutionary contributions in the value chain of precious metal. Augmont’s unique DNA makes it our responsibility to revolutionize the entire gold ecosystem and help people transform their dreams into reality via easy access to gold.

It is a ‘Phygital’ business model through which we sell various gold products like Gold Loan, Digi Gold, EMI Gold, Sell Old Gold, and many more through our deeply entrenched jeweller franchise network, doorstep delivery, and our digital platform (web and app).

With Augmont Gold For All, we have simplified gold and the process across its lifecycle. Our gold tech ecosystem is aimed to make gold a life enabler for our consumers as well as for our jeweller partners.

VISION

Glittering a billion lives through the power of Gold

MISSION

To make Gold a life enabler for all our stakeholders

LEADING PIONEERS IN GOLD IN INDIA

Among India’s most reputed refinery & bullion companies with deep inroads in the close-knit jeweller community

Ability to financially hedge with the most efficient and effective price discovery

Physically deliver across exchanges, ETFs, and other channels

Capable of distributing bullion from 0.1 grams coins to 1 kg bars across India

More flexible and adaptive to changes in government policies

Operates at lower costs than international refineries with the same level of efficiency, if not better

Scale of Operations - Among the largest

Leading Gold Refinery in India with annual sales surpassing US$ 3 bn

Leading creator and redeemer of gold exchange-traded fund (ETF) units in India on all gold ETF schemes

Leading delivery provider of gold on commodity exchanges in India


ACCREDITATIONS AND ACCOMPLISHMENTS

Augmont’s prices are used as the most common reference prices across India

The refinery is accredited by BIS and NABL

Awarded as the best platform and leading refinery year on year since 2009

"India Good Delivery” member for NSE and MCX

THE TRAILBLAZERS

Augmont has created an extremely strong brand name in the retail space and as well among the jewellers (fraternity). The brand is the preferred partner among the retail and merchants due to the inevitable ecosystem developed that covers the entire value chain.

Augmont has been at the forefront of innovation.

SPOT – World’s largest and India’s first physical gold/silver/platinum platform since 2008

Bullion ++ - Borrowing & Lending of Gold

Bullion India – India’s pioneer digital gold platform (rebranded as Augmont Digi-gold)

OCDs- India’s first Optionally Convertible Debentures for commodities markets

Bullion Futures - Instrumental in successfully devising delivery based contracts for gold & silver on commodity exchanges

ETFs - World’s first Gold ETF was conceptualized by Augmont as Paper Gold in 2002 and was filed with SEBI.

EMI Jewellery - World's largest investible jewelry product, in tamper-proof packaging. We are the pioneers in making Gold accessible to all.

Augmont’s innovations have helped the jewellers in addressing the defaults and frauds of bullion brokers. Transparent pricing has saved 100s of crores of Rupees for jewellers/end consumers while buying gold.
''';