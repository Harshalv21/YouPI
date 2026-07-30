import 'package:flutter/material.dart';

class LegalSection {
  final String heading;
  final String body;
  const LegalSection({required this.heading, required this.body});
}

class LegalDocumentScaffold extends StatelessWidget {
  final String title;
  final String lastUpdated;
  final List<LegalSection> sections;

  const LegalDocumentScaffold({
    super.key,
    required this.title,
    required this.lastUpdated,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white70),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Last updated: $lastUpdated',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 20),
          for (final section in sections) ...[
            Text(
              section.heading,
              style: const TextStyle(
                color: Color(0xFF2ECC9B), // teal accent, matches app
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              section.body,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13.5,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }
}