import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../content/legal_documents.dart';
import '../model/legal_document.dart';
import 'legal_document_screen.dart';

ValueKey<String> legalDocumentTileKey(String documentId) =>
    ValueKey<String>('legal-document-$documentId');

/// Offline index of AgroBenta's bundled legal-document drafts.
class TermsAndPoliciesScreen extends StatelessWidget {
  const TermsAndPoliciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Terms and Policies')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Learn about your rights, responsibilities, and how '
                      'AgroBenta operates.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: <Widget>[
                          for (
                            int index = 0;
                            index < LegalDocuments.all.length;
                            index++
                          ) ...<Widget>[
                            if (index > 0) const Divider(height: 1),
                            _PolicyMenuItem(
                              document: LegalDocuments.all[index],
                              onTap: () => _openDocument(
                                context,
                                LegalDocuments.all[index],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDocument(BuildContext context, LegalDocument document) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            LegalDocumentScreen(document: document),
      ),
    );
  }
}

class _PolicyMenuItem extends StatelessWidget {
  const _PolicyMenuItem({required this.document, required this.onTap});

  final LegalDocument document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${document.title}. ${document.description}',
      child: ListTile(
        key: legalDocumentTileKey(document.id),
        minVerticalPadding: AppSpacing.xs,
        leading: Icon(document.icon, semanticLabel: document.title),
        title: Text(document.title),
        subtitle: Text(document.description),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
