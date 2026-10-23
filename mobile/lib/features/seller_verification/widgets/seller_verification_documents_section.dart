import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/seller_verification.dart';
import '../../../repositories/seller_verification_repository.dart';
import '../state/seller_verification_scope.dart';
import '../../../widgets/section_card.dart';

/// The "Uploaded Documents" section of the status screen (doc 06).
///
/// Lists the two required documents and whether each is on file, read from the
/// record's `has_id_document` / `has_selfie` flags — never from a path or URL,
/// which the mobile resource does not expose. Each document that is on file
/// offers a secure `View`, which streams the bytes through the authenticated
/// endpoint; nothing here is a public URL.
class SellerVerificationDocumentsSection extends StatelessWidget {
  const SellerVerificationDocumentsSection({
    required this.verification,
    super.key,
  });

  final SellerVerification verification;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Uploaded Documents',
      children: <Widget>[
        _DocumentRow(
          label: 'Government-Issued ID',
          type: VerificationDocumentType.idDocument,
          present: verification.hasIdDocument,
        ),
        const SizedBox(height: AppSpacing.xs),
        _DocumentRow(
          label: 'Selfie Holding ID',
          type: VerificationDocumentType.selfie,
          present: verification.hasSelfie,
        ),
      ],
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.label,
    required this.type,
    required this.present,
  });

  final String label;
  final VerificationDocumentType type;
  final bool present;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Icon(
          present ? Icons.description_outlined : Icons.remove_circle_outline,
          size: 20,
          color: present ? AppColors.primary : AppColors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: theme.textTheme.bodyMedium),
              Text(
                present ? 'On file' : 'Not on file',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (present)
          // Enabled only when the document is actually on file: a View button
          // for a document the server does not hold would be a dead control.
          TextButton(
            onPressed: () => _view(context),
            child: const Text('View'),
          ),
      ],
    );
  }

  Future<void> _view(BuildContext context) async {
    final SellerVerificationRepository repository =
        SellerVerificationScope.repositoryOf(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) => _DocumentDialog(
        label: label,
        future: repository.fetchDocument(type),
      ),
    );
  }
}

/// The secure preview for one document: bytes fetched from the authenticated
/// endpoint, rendered as an image, with a failure state that never leaks a URL.
class _DocumentDialog extends StatefulWidget {
  const _DocumentDialog({required this.label, required this.future});

  final String label;
  final Future<Uint8List?> future;

  @override
  State<_DocumentDialog> createState() => _DocumentDialogState();
}

class _DocumentDialogState extends State<_DocumentDialog> {
  late final Future<Uint8List?> _future = widget.future;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.label,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<Uint8List?>(
                future: _future,
                builder: (
                  BuildContext context,
                  AsyncSnapshot<Uint8List?> snapshot,
                ) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.xxl),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    final Object error = snapshot.error!;
                    final String message = error is ApiException
                        ? error.message
                        : 'Could not load this document.';
                    return _DialogMessage(
                      icon: Icons.cloud_off_outlined,
                      message: message,
                    );
                  }

                  final Uint8List? bytes = snapshot.data;
                  if (bytes == null || bytes.isEmpty) {
                    // A `null` here is the repository's translation of a 404:
                    // the record claimed a document but none is stored. Report
                    // it honestly rather than showing a broken image.
                    return _DialogMessage(
                      icon: Icons.image_not_supported_outlined,
                      message: 'This document is not available.',
                    );
                  }

                  return InteractiveViewer(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder:
                          (BuildContext context, Object error, StackTrace? _) =>
                              const _DialogMessage(
                                icon: Icons.image_not_supported_outlined,
                                message: 'This document could not be displayed.',
                              ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogMessage extends StatelessWidget {
  const _DialogMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 40, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
