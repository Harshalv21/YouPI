import 'package:flutter/material.dart';
import '../../core/widgets/legal_document_scaffold.dart';

// PLACEHOLDER CONTENT -- no refund policy text was supplied by legal/
// director as of this writing. Sections below are structural placeholders
// only, so the screen is wired and reachable, but every body string here
// needs to be replaced with actual reviewed policy text before this goes
// live -- none of it should be treated as real legal copy.
class RefundPolicyScreen extends StatelessWidget {
  const RefundPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalDocumentScaffold(
      title: 'Refund Policy',
      lastUpdated: 'Not yet finalized',
      sections: const [
        LegalSection(
          heading: '1. Refund Eligibility',
          body: '[PLACEHOLDER -- content pending legal/director review. '
              'Specify which transaction types (wallet top-up, recharge, '
              'Gold FD, Digital Gold buy/sell, etc.) are eligible for a '
              'refund and under what conditions.]',
        ),
        LegalSection(
          heading: '2. Non-Refundable Transactions',
          body: '[PLACEHOLDER -- e.g. completed Digital Gold buy/sell '
              'transactions are typically non-cancellable once placed, '
              'per Augmont\'s own terms -- confirm and state explicitly '
              'here.]',
        ),
        LegalSection(
          heading: '3. Refund Processing Timeline',
          body: '[PLACEHOLDER -- specify expected processing time and '
              'the bank/wallet route funds are returned through.]',
        ),
        LegalSection(
          heading: '4. How to Request a Refund',
          body: '[PLACEHOLDER -- specify the in-app flow or support '
              'contact for raising a refund request.]',
        ),
        LegalSection(
          heading: '5. Contact Us',
          body: '[PLACEHOLDER -- support email/phone for refund queries.]',
        ),
      ],
    );
  }
}