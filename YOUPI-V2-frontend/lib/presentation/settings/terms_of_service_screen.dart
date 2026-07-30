import 'package:flutter/material.dart';
import '../../core/widgets/legal_document_scaffold.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalDocumentScaffold(
      title: 'Terms of Service',
      lastUpdated: '30 July 2026',
      sections: const [
        LegalSection(
          heading: '1. About YouPi',
          body:
              'YouPi is a financial technology platform operated by Nexospendz Finothrive Private Limited, registered office in Lucknow, Uttar Pradesh, India. YouPi offers:\n\n'
              '• SmartSave — telecom recharge on installment / deferred-payment basis\n'
              '• SmartInvest — purchase, holding, and sale of digital gold via our vaulting/custody partner\n'
              '• YouPi Credit — digital lending, with YouPi as Lending Service Provider for regulated Lending Partners\n'
              '• YouPi Score — a proprietary loyalty and eligibility rating\n\n'
              'Where a product-specific term conflicts with these general Terms, the product-specific term prevails for that Service.',
        ),
        LegalSection(
          heading: '2. Key Definitions',
          body:
              'Augmont — our vaulting, custody, and fulfilment partner for SmartInvest.\n'
              'Digital Gold — fractional units of 24 karat / 999.9 purity gold held by the custody partner.\n'
              'KYC — identity verification including PAN, Aadhaar and other documents.\n'
              'KFS (Key Fact Statement) — key loan terms provided before any loan is availed.\n'
              'Lending Partner — an RBI-regulated bank or NBFC that extends credit under YouPi Credit.\n'
              'LSP — the role YouPi operates in for YouPi Credit under RBI\'s digital lending framework.',
        ),
        LegalSection(
          heading: '3. Eligibility',
          body:
              'To use the Platform, you must be a natural person aged 18+, a resident of India with a valid Indian mobile number, possess a valid PAN and required KYC documents, have legal capacity to contract, and not be barred under Applicable Law or partner terms. YouPi Credit may carry additional eligibility criteria set by us or the Lending Partner.',
        ),
        LegalSection(
          heading: '4. Account Registration and KYC',
          body:
              'You must register an Account and are responsible for keeping login credentials and OTPs confidential. You authorise YouPi and KYC/verification partners (including Eko Platform Services or others we appoint) to verify your identity, including PAN, against authorised sources. KYC must be completed before using SmartInvest and YouPi Credit. One User may hold only one Account unless expressly permitted otherwise.',
        ),
        LegalSection(
          heading: '5. SmartSave (Telecom Recharge — Installment / Deferred Payment)',
          body:
              'SmartSave allows an immediate Recharge with payment in installments or on a deferred basis, on terms shown at the time of transaction. Recharges are fulfilled via telecom operators/authorised channels — YouPi does not control network availability or crediting of talktime/data. You agree to repay each SmartSave amount plus disclosed fees by the due date(s). If a Recharge fails, we will re-attempt or refund on operator verification. Bulk, commercial, fraudulent, or reseller use is prohibited.',
        ),
        LegalSection(
          heading: '6. SmartInvest (Digital Gold)',
          body:
              'SmartInvest enables buying, accumulating, and selling Digital Gold (999.9 purity) held by our custody partner (Augmont). PAN-based KYC is required before any buy/sell. Buy and sell prices are set by the custody partner and fluctuate with market rates, inclusive of applicable taxes and a buy-sell spread.\n\n'
              'Cashback: SmartInvest may offer promotional cashback (currently up to 1% in Digital Gold), discretionary and subject to change or withdrawal at any time.\n\n'
              'Redemption: You may sell Digital Gold back at the prevailing sell price, credited to your verified bank account. Physical delivery, where offered, is subject to minimum quantities and charges.\n\n'
              'Risk disclosure: Digital Gold is not a security, not SEBI-regulated, not a deposit, not RBI-guaranteed, and not covered by deposit insurance. Value can go up or down; past performance does not indicate future returns. SmartInvest is not investment advice.',
        ),
        LegalSection(
          heading: '7. YouPi Credit — Digital Lending',
          body:
              'YouPi acts solely as a Lending Service Provider (LSP) on behalf of RBI-regulated Lending Partners. YouPi does not lend from its own books — every loan is a contract between you and the Lending Partner.\n\n'
              'Per RBI\'s Digital Lending framework:\n'
              '• You receive a Key Fact Statement (KFS) before accepting any loan, disclosing amount, tenure, APR, fees, recovery mechanism, and grievance officer\n'
              '• Disbursement and repayment flow directly between your bank account and the Lending Partner\n'
              '• YouPi charges you no fee for lending-related services — any fee is paid by the Lending Partner\n'
              '• You may exit within the cooling-off period in your KFS by repaying principal + proportionate APR, penalty-free\n'
              '• Your credit limit will not be increased without your explicit consent\n\n'
              'YouPi Credit may offer an interest-free tranche (e.g. up to ₹2,000) and a paid credit limit at the APR in your KFS. Default may lead to additional charges, credit bureau reporting, and lawful recovery action. Approval and terms are at the sole discretion of the Lending Partner.',
        ),
        LegalSection(
          heading: '8. YouPi Score',
          body:
              'YouPi Score is a proprietary loyalty and eligibility tier based on your engagement and conduct on the Platform. It is not a credit score issued by a credit information company (e.g. CIBIL), is not a guarantee of credit, and is not collateral. Methodology, tiers, and benefits may be changed by us at any time without prior notice.',
        ),
        LegalSection(
          heading: '9. Third-Party Services and Partners',
          body:
              'Services rely on partners including Augmont (custody), Eko Platform Services (KYC/verification), Lending Partners, telecom operators, and payment gateways. We are not responsible for the acts, omissions, or independent decisions of third-party partners, except as required by Applicable Law. We may add, change, or replace partners from time to time.',
        ),
        LegalSection(
          heading: '10. Fees, Charges, and Taxes',
          body:
              'Fees are disclosed before you incur them — for SmartSave at the transaction, for SmartInvest in the price shown, for YouPi Credit in the KFS. All amounts are inclusive of/subject to applicable taxes (including GST). We may revise fees prospectively with notice.',
        ),
        LegalSection(
          heading: '11. User Obligations and Prohibited Conduct',
          body:
              'You agree not to: provide false or fraudulent information or impersonate anyone; use the Platform for money laundering, terrorist financing, or unlawful purposes; use another person\'s PAN, bank account, or identity; resell or commercially exploit any Service; attempt unauthorised access, reverse-engineering, or scraping; upload malicious code; or violate Applicable Law or third-party rights. You are responsible for the accuracy of your registered bank account and mobile number.',
        ),
        LegalSection(
          heading: '12. Intellectual Property',
          body:
              'All IP in the Platform — the "YouPi" name/logo, "SmartSave", "SmartInvest", "YouPi Credit", "YouPi Score", software, designs, and content — is owned by or licensed to YouPi. You get a limited, non-exclusive, revocable licence to use the Platform; no rights are transferred to you.',
        ),
        LegalSection(
          heading: '13. Data Protection and Privacy',
          body:
              'Our collection, use, storage, and sharing of your data is governed by our Privacy Policy and the DPDP Act, RBI directions (including data localisation), and other Applicable Law. We collect only data necessary for the Services and do not access your phone\'s contacts, media, or files except with explicit, purpose-limited consent.',
        ),
        LegalSection(
          heading: '14. Grievance Redressal',
          body:
            "Contact connect@you-pi.in or use in-app support for any queries, support requests, or complaints. For YouPi Credit, unresolved complaints may be escalated to the Lending Partner's grievance/nodal officer (as mentioned in your KFS) and then to RBI's Integrated Ombudsman mechanism, where applicable.",
        ),
        LegalSection(
          heading: '15. Disclaimers',
          body:
              'The Platform is provided "as is" and "as available", with no warranties to the extent permitted by law. We do not provide investment, tax, legal, or financial advice. We do not guarantee availability, timing, or outcome of Recharges, Digital Gold transactions, loan approvals, or third-party services.',
        ),
        LegalSection(
          heading: '16. Limitation of Liability',
          body:
              'YouPi and its directors, employees, and affiliates are not liable for indirect, incidental, consequential, or punitive damages, or loss of profits, goodwill, or data. Aggregate liability for any claim is limited to the fees actually received by YouPi from you for that transaction. This does not limit liability that cannot be excluded by law, including fraud or wilful misconduct.',
        ),
        LegalSection(
          heading: '17. Indemnity',
          body:
              'You agree to indemnify YouPi, its directors, employees, and partners against claims, losses, and expenses arising from your breach of these Terms, violation of Applicable Law or third-party rights, or misuse of your Account attributable to you.',
        ),
        LegalSection(
          heading: '18. Suspension and Termination',
          body:
              'We may suspend, restrict, or terminate access if you breach these Terms or law, if fraud/money laundering/misuse is suspected, if required by a regulator/Lending Partner/court, or if we discontinue a Service. Termination doesn\'t affect accrued rights, outstanding repayment obligations, or your Digital Gold holdings (governed by the custody partner\'s terms).',
        ),
        LegalSection(
          heading: '19. Force Majeure',
          body:
              'We are not liable for failure or delay caused by events beyond our reasonable control, including acts of God, pandemics, network/power failures, banking or telecom outages, cyber-attacks, regulatory action, or partner failures.',
        ),
        LegalSection(
          heading: '20. Changes to These Terms',
          body:
              'We may amend these Terms, fees, or Services from time to time. Material changes will be notified through the Platform. Changes affecting existing loans will follow RBI\'s notice and consent requirements. Continued use after the effective date constitutes acceptance.',
        ),
        LegalSection(
          heading: '21. Governing Law and Dispute Resolution',
          body:
              'These Terms are governed by the laws of India. Courts at Lucknow, Uttar Pradesh have exclusive jurisdiction, without prejudice to any statutory grievance or ombudsman mechanism. Disputes may, at the Company\'s election, be referred to arbitration under the Arbitration and Conciliation Act, 1996, seated in Lucknow, in English.',
        ),
        LegalSection(
          heading: '22. Miscellaneous',
          body:
              'These Terms, the Privacy Policy, and any product-specific terms/KFS form the entire agreement. If any provision is invalid, the rest continues in effect. Failure to enforce a provision is not a waiver. You may not assign these Terms; we may assign ours to an affiliate, successor, or acquirer. Notices may be sent via the Platform, SMS, email, or your registered contact details. English version prevails over any translation.',
        ),
        LegalSection(
          heading: '23. Contact',
          body:
              'Nexospendz Finothrive Private Limited\n'
              'Registered office: Lucknow, Uttar Pradesh, India\n'
              'Website: you-pi.in\n'
              'Support: connect@you-pi.in',
        ),
      ],
    );
  }
}