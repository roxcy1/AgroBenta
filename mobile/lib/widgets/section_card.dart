import 'package:flutter/material.dart';

import '../core/theme/app_spacing.dart';

/// A titled card grouping related rows or content.
///
/// The standard container for a labelled section on a detail screen or form:
/// one title, a short gap, then the section's content. Cards rather than a flat
/// run of content, so a long screen reads as sections instead of one scroll.
class SectionCard extends StatelessWidget {
  const SectionCard({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            ...children,
          ],
        ),
      ),
    );
  }
}