import 'package:flutter/material.dart';
import '../../core/widgets/legal_document_scaffold.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalDocumentScaffold(
      title: 'Privacy Policy',
      lastUpdated: '30 July 2026',
      sections: const [
        LegalSection(
          heading: '1. Who We Are',
          body:
              'YouPi (Nexospendz Finothrive Private Limited) is a company incorporated under the Companies Act, 2013, with its registered office in Lucknow, Uttar Pradesh, India. We are responsible for the personal data we process about you on the Platform.\n\n'
              'For YouPi Credit, some processing is carried out on behalf of, or together with, our regulated Lending Partners (banks / NBFCs), who are separately responsible for the data relating to the loan they extend to you.',
        ),
        LegalSection(
          heading: '2. The Data We Collect',
          body:
              'Identity and KYC data: Full name, date of birth, gender, PAN and PAN verification results, Aadhaar / other officially valid documents, photograph / selfie where required.\n\n'
              'Contact data: Mobile number, email address, communication and postal address.\n\n'
              'Financial and transaction data: Bank account details for disbursement, repayment and redemption, transaction history (SmartSave, SmartInvest, YouPi Credit), Digital Gold holdings, YouPi Score.\n\n'
              'Device and technical data: Device model, OS, unique identifiers, IP address, app version, log data, cookies, app usage analytics.\n\n'
              'Location data: Approximate (coarse) location only, for fraud prevention, service eligibility, or regulatory compliance. We do not track continuous or real-time location.\n\n'
              'What we do NOT access: In line with RBI\'s digital-lending requirements, we do not access your phone\'s contact list, call logs, media, photo gallery, or files. Permissions like camera (KYC) or SMS read (OTP auto-read) are purpose-limited and consent-based.',
        ),
        LegalSection(
          heading: '3. How We Collect Your Data',
          body:
              'Directly from you — during registration, KYC, adding a bank account, or transacting.\n\n'
              'Automatically — through device and usage data.\n\n'
              'From authorised partners — KYC/verification partner, custody partner (Digital Gold), Lending Partners, payment gateways, and authorised verification sources.',
        ),
        LegalSection(
          heading: '4. Why We Use Your Data',
          body:
              'Providing the Services (registration, SmartSave recharges/installments, SmartInvest buy/sell, YouPi Credit loans)\n'
              '• KYC and identity verification\n'
              '• Credit facilitation for YouPi Credit (sharing data with Lending Partners)\n'
              '• Fraud prevention and security\n'
              '• Regulatory and legal compliance (DPDP Act, RBI, PMLA, tax laws)\n'
              '• Communication (transaction alerts, updates, complaints, and consented offers)\n'
              '• Improving the Platform\n'
              '• Computing YouPi Score\n\n'
              'We will not use your data for a new, unrelated purpose without fresh consent where required by law.',
        ),
        LegalSection(
          heading: '5. Consent and Your Choices',
          body:
              'We process your data based on your consent and, where applicable, legitimate uses and legal obligations under the DPDP Act. Consent is sought at or before collection, and is specific and informed. You can withdraw consent anytime through the Platform or by writing to us. Withdrawal does not affect processing already carried out and may make certain Services unavailable.\n\n'
              'Where law requires retention (e.g. KYC and loan records), we may continue processing even after you stop using the Platform.',
        ),
        LegalSection(
          heading: '6. Who We Share Your Data With',
          body:
              'We do not sell your personal data. We share it only with:\n\n'
              '• Lending Partners (banks/NBFCs) — for YouPi Credit assessment, sanction, servicing and recovery\n'
              '• Our custody/vaulting partner — for SmartInvest Digital Gold\n'
              '• Our KYC/verification partner — for PAN and identity verification\n'
              '• Telecom operators and distribution channels — to fulfil SmartSave recharges\n'
              '• Payment gateways and banking partners\n'
              '• Credit information companies — as applicable, by the Lending Partner\n'
              '• Service providers (cloud hosting, communication, analytics, support)\n'
              '• Regulators, courts, and authorities — where legally required\n'
              '• In a business transfer — to a successor or acquirer, subject to this Policy and law\n\n'
              'All third parties are required to protect your data and use it only for disclosed purposes.',
        ),
        LegalSection(
          heading: '7. Data Storage, Localisation, and Security',
          body:
              'In accordance with RBI directions, data relating to your transactions and credit facilities is stored on servers located in India.\n\n'
              'We use reasonable technical and organisational safeguards, including encryption in transit, access controls, and secure infrastructure.\n\n'
              'We do not store your biometric data — Aadhaar-based biometric authentication is performed through authorised channels only.\n\n'
              'In the event of a data breach, we will notify the Data Protection Board of India and affected Users as required under the DPDP Act.\n\n'
              'No method of transmission or storage is completely secure; we cannot guarantee absolute security.',
        ),
        LegalSection(
          heading: '8. Data Retention',
          body:
              'We keep your personal data only as long as necessary to provide the Services, comply with legal/regulatory/tax/KYC obligations, and to establish, exercise, or defend legal claims. KYC and loan-related records are retained for the period mandated under Applicable Law (RBI, PMLA) after the relationship or loan ends. Data no longer required is securely deleted or anonymised.',
        ),
        LegalSection(
          heading: '9. Your Rights',
          body:
              'Under the DPDP Act, subject to its conditions and exemptions, you have the right to:\n\n'
              '• Access — a summary of the personal data we process about you\n'
              '• Correction and updating — of inaccurate or incomplete data\n'
              '• Erasure — of data no longer required, where law does not require retention\n'
              '• Withdraw consent — anytime\n'
              '• Raise a complaint — about how we handle your data\n'
              '• Nominate — another person to exercise your rights in case of death or incapacity\n\n'
              'To exercise these rights, contact us using the details in Section 12. We may verify your identity before acting.',
        ),
        LegalSection(
          heading: '10. Your Responsibilities',
          body:
              'You agree to provide accurate and complete information, keep it updated, and not submit false information or impersonate another person.',
        ),
        LegalSection(
          heading: '11. Children',
          body:
              'The Platform is intended only for individuals aged 18 years and above. We do not knowingly collect personal data from anyone under 18. If we learn that we have, we will delete it.',
        ),
        LegalSection(
          heading: '12. How to Contact Us',
          body:
              'Data / privacy queries: privacy@you-pi.in\n'
              'Complaints: grievance@you-pi.in\n'
              'By post: Nexospendz Finothrive Private Limited, Lucknow, Uttar Pradesh, India\n\n'
              'We will acknowledge and respond within timelines prescribed under Applicable Law. If unsatisfied, you may escalate to the Data Protection Board of India, or for YouPi Credit matters, to the Lending Partner\'s grievance channel and RBI\'s integrated ombudsman mechanism.',
        ),
        LegalSection(
          heading: '13. Cookies and Analytics',
          body:
              'We and our analytics providers use cookies and similar technologies to operate the Platform, remember preferences, and understand usage. You can manage cookies via browser/device settings; disabling them may affect functionality.',
        ),
        LegalSection(
          heading: '14. Third-Party Links and Services',
          body:
              'The Platform may link to or integrate third-party services (e.g. partner or payment pages), governed by their own privacy policies. We are not responsible for their practices.',
        ),
        LegalSection(
          heading: '15. Changes to This Policy',
          body:
              'We may update this Policy from time to time. Material changes will be notified through the Platform. Continued use after changes take effect means you accept the updated Policy.',
        ),
        LegalSection(
          heading: '16. Company Details',
          body:
              'Nexospendz Finothrive Private Limited\n'
              'Registered office: Lucknow, Uttar Pradesh, India\n'
              'Website: you-pi.in\n'
              'Privacy queries: privacy@you-pi.in | Complaints: grievance@you-pi.in',
        ),
      ],
    );
  }
}