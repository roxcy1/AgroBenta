import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../content/legal_metadata.dart';
import '../model/legal_document.dart';

/// Reusable, accessible reader for one locally bundled legal document.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({required this.document, super.key});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, 3.0).toDouble();
    final List<Widget> documentContent = <Widget>[
      Text(document.title, style: theme.textTheme.headlineSmall),
      if (LegalMetadata.effectiveDate != null ||
          LegalMetadata.lastUpdatedDate != null) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xxs,
          children: <Widget>[
            if (LegalMetadata.effectiveDate case final String date)
              _DateLabel(label: 'Effective', value: date),
            if (LegalMetadata.lastUpdatedDate case final String date)
              _DateLabel(label: 'Last updated', value: date),
          ],
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      Text(document.introduction, style: theme.textTheme.bodyLarge),
    ];

    for (int index = 0; index < document.sections.length; index++) {
      final LegalSection section = document.sections[index];
      documentContent.addAll(<Widget>[
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            '${index + 1}. ${section.heading}',
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (
          int paragraph = 0;
          paragraph < section.paragraphs.length;
          paragraph++
        ) ...<Widget>[
          if (paragraph > 0) const SizedBox(height: AppSpacing.sm),
          Text(section.paragraphs[paragraph], style: theme.textTheme.bodyLarge),
        ],
        if (section.bullets.isNotEmpty) ...<Widget>[
          if (section.paragraphs.isNotEmpty)
            const SizedBox(height: AppSpacing.sm),
          for (final String bullet in section.bullets)
            _LegalBullet(text: bullet),
        ],
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: AppSizes.appBarHeight + (textScale - 1) * 44,
        title: Text(
          document.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          key: ValueKey<String>('legal-document-scroll-${document.id}'),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            MediaQuery.viewPaddingOf(context).bottom + AppSpacing.xxl,
          ),
          children: <Widget>[
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: documentContent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateLabel extends StatelessWidget {
  const _DateLabel({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $value',
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
    );
  }
}

class _LegalBullet extends StatelessWidget {
  const _LegalBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 9, right: AppSpacing.sm),
            child: ExcludeSemantics(
              child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
