import 'package:flutter/material.dart';

/// A self-contained, locally bundled legal document shown by the mobile app.
///
/// Presentation stays in the terms-and-policies views; copy and document
/// metadata stay in the feature's content files so policy updates do not
/// require duplicating screen layouts.
@immutable
class LegalDocument {
  const LegalDocument({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.introduction,
    required this.sections,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final String introduction;
  final List<LegalSection> sections;
}

@immutable
class LegalSection {
  const LegalSection({
    required this.heading,
    this.paragraphs = const <String>[],
    this.bullets = const <String>[],
  });

  final String heading;
  final List<String> paragraphs;
  final List<String> bullets;
}
