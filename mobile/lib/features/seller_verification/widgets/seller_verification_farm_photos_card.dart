import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../state/seller_verification_documents_state.dart';
import '../view/seller_verification_documents.dart';

/// The optional farm photos in the application form.
///
/// Like `SellerVerificationDocumentCard`, a pure render of its state: each photo
/// shows a state word, and only one the server confirmed reads "Uploaded".
class SellerVerificationFarmPhotosCard extends StatelessWidget {
  const SellerVerificationFarmPhotosCard({
    required this.documents,
    required this.onAdd,
    required this.onRemove,
    required this.onRetry,
    super.key,
  });

  final SellerVerificationDocumentsState documents;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<VerificationDocument> photos = documents.farmPhotos;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('Farm Photos', style: theme.textTheme.titleSmall),
                ),
                Text(
                  'Optional',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Add photos of your livestock or farm area, up to '
              '$kMaxVerificationFarmPhotos.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (int index = 0; index < photos.length; index++)
              _PhotoRow(
                position: index + 1,
                photo: photos[index],
                onRemove: documents.isBusy ? null : () => onRemove(index),
                onRetry: documents.isBusy ? null : () => onRetry(index),
              ),
            OutlinedButton.icon(
              onPressed: documents.canAddFarmPhoto ? onAdd : null,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Add Photo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.position,
    required this.photo,
    required this.onRemove,
    required this.onRetry,
  });

  final int position;
  final VerificationDocument photo;
  final VoidCallback? onRemove;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool failed = photo.status == VerificationDocumentStatus.failed;

    final (String label, Color color) = switch (photo.status) {
      VerificationDocumentStatus.uploading => ('Working…', AppColors.primary),
      VerificationDocumentStatus.uploaded => ('Uploaded', AppColors.success),
      VerificationDocumentStatus.needsUpload => (
        'Upload required',
        AppColors.error,
      ),
      VerificationDocumentStatus.failed => ('Upload failed', AppColors.error),
      _ => ('Not uploaded', AppColors.textSecondary),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Photo $position', style: theme.textTheme.bodyMedium),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
                if (photo.error != null)
                  Text(
                    photo.error!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.error,
                    ),
                  ),
              ],
            ),
          ),
          if (failed)
            IconButton(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              tooltip: 'Retry photo $position',
            ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove photo $position',
          ),
        ],
      ),
    );
  }
}
