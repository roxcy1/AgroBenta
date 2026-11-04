import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../widgets/local_image_preview.dart';
import '../state/seller_verification_documents_state.dart';

/// One required-document card in the application form: a title, an instruction,
/// a preview, and the pick/change/remove controls.
///
/// The card is a pure render of the slot it is handed — it owns no request and
/// decides nothing. The state word is what carries the meaning ("Uploading",
/// "Uploaded", "Upload failed"), matching the rule that a colour alone must not
/// be the only signal.
class SellerVerificationDocumentCard extends StatelessWidget {
  const SellerVerificationDocumentCard({
    required this.title,
    required this.instruction,
    required this.qualityGuidance,
    required this.document,
    required this.onPick,
    required this.onRemove,
    required this.onRetry,
    this.onRetryPreview,
    this.pickLabel = 'Choose Image',
    this.changeLabel = 'Change',
    super.key,
  });

  /// Card heading, e.g. "Valid Government-Issued ID".
  final String title;

  /// What the document must show.
  final String instruction;

  /// Concise image-quality guidance.
  final String qualityGuidance;

  /// The slot this card renders.
  final VerificationDocument document;

  /// Opens the picker (camera or gallery).
  final VoidCallback onPick;

  /// Removes the current selection, locally and — if staged — on the server.
  final VoidCallback onRemove;

  /// Retries a failed upload.
  final VoidCallback onRetry;

  /// Retries loading an already-uploaded document preview after a fetch failure.
  final VoidCallback? onRetryPreview;

  /// Label for the first pick action, e.g. "Take Photo".
  final String pickLabel;

  /// Label for the replace action once a file is present, e.g. "Change".
  final String changeLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                const _RequiredChip(),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(instruction, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            _Preview(document: document, onRetryPreview: onRetryPreview),
            const SizedBox(height: AppSpacing.xs),
            _StatusLine(document: document),
            const SizedBox(height: AppSpacing.sm),
            Text(
              qualityGuidance,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Actions(
              document: document,
              pickLabel: pickLabel,
              changeLabel: changeLabel,
              onPick: onPick,
              onRemove: onRemove,
              onRetry: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _RequiredChip extends StatelessWidget {
  const _RequiredChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        'Required',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

/// A neutral placeholder, a local-file preview, or an uploaded indicator.
class _Preview extends StatelessWidget {
  const _Preview({required this.document, this.onRetryPreview});

  final VerificationDocument document;
  final VoidCallback? onRetryPreview;

  static const double _height = 160;

  @override
  Widget build(BuildContext context) {
    final XFile? file = document.file;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        height: _height,
        width: double.infinity,
        color: AppColors.background,
        child: switch (document.status) {
          VerificationDocumentStatus.uploading => const _UploadingOverlay(),
          _ when file != null => LocalImagePreview(
            file: file,
            fit: BoxFit.contain,
            fallback: const _EmptyPlaceholder(),
          ),
          _ when document.hasPreviousRecordDocument => _remotePreview(),
          _ when !document.isUploaded => const _EmptyPlaceholder(),
          _ => _remotePreview(),
        },
      ),
    );
  }

  Widget _remotePreview() {
    return switch (document.previewStatus) {
      VerificationDocumentPreviewStatus.loading => const _PreviewLoading(),
      VerificationDocumentPreviewStatus.loaded =>
        document.previewBytes == null
            ? const _UnavailablePlaceholder(
                message: 'This document could not be displayed.',
              )
            : Image.memory(
                document.previewBytes!,
                fit: BoxFit.contain,
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? _) =>
                        const _UnavailablePlaceholder(
                          message: 'This document could not be displayed.',
                        ),
                excludeFromSemantics: true,
              ),
      VerificationDocumentPreviewStatus.failed => _PreviewFailure(
        message: document.previewError ?? 'Could not load this document.',
        retryable: document.previewRetryable,
        onRetry: onRetryPreview,
      ),
      VerificationDocumentPreviewStatus.missing =>
        const _UnavailablePlaceholder(
          message: 'This document is not available.',
        ),
      VerificationDocumentPreviewStatus.idle => const _UploadedPlaceholder(),
    };
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.add_photo_alternate_outlined,
            size: 32,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'No image selected',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _UploadedPlaceholder extends StatelessWidget {
  const _UploadedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.check_circle, size: 32, color: AppColors.success),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Uploaded',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.success),
          ),
        ],
      ),
    );
  }
}

class _UnavailablePlaceholder extends StatelessWidget {
  const _UnavailablePlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.image_not_supported_outlined,
              size: 32,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewLoading extends StatelessWidget {
  const _PreviewLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    );
  }
}

class _PreviewFailure extends StatelessWidget {
  const _PreviewFailure({
    required this.message,
    required this.retryable,
    required this.onRetry,
  });

  final String message;
  final bool retryable;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_outlined,
              color: AppColors.textSecondary,
              size: 28,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
            if (retryable && onRetry != null)
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry preview'),
              ),
          ],
        ),
      ),
    );
  }
}

class _UploadingOverlay extends StatelessWidget {
  const _UploadingOverlay();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    );
  }
}

/// The one-line state word plus any failure message.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.document});

  final VerificationDocument document;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final (String label, Color color) = switch (document.status) {
      VerificationDocumentStatus.empty => (
        'Not selected',
        AppColors.textSecondary,
      ),
      VerificationDocumentStatus.selected => (
        'Selected — not yet uploaded',
        AppColors.textSecondary,
      ),
      VerificationDocumentStatus.uploading => ('Uploading…', AppColors.primary),
      VerificationDocumentStatus.uploaded => ('Uploaded', AppColors.success),
      VerificationDocumentStatus.needsUpload => (
        'Upload required',
        AppColors.error,
      ),
      VerificationDocumentStatus.failed => ('Upload failed', AppColors.error),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: color)),
        if ((document.status == VerificationDocumentStatus.failed ||
                document.status == VerificationDocumentStatus.needsUpload) &&
            document.error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            document.error!,
            style: theme.textTheme.labelSmall?.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

/// Pick / change / remove / retry, depending on the slot's state.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.document,
    required this.pickLabel,
    required this.changeLabel,
    required this.onPick,
    required this.onRemove,
    required this.onRetry,
  });

  final VerificationDocument document;
  final String pickLabel;
  final String changeLabel;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (document.isUploading) {
      // No action while a request is in flight; the button is not merely
      // disabled, it is absent, so a tap cannot queue a second upload.
      return const SizedBox.shrink();
    }

    final bool hasFile = document.hasFile;
    final bool isUploaded = document.isUploaded;
    final bool hasFailed = document.status == VerificationDocumentStatus.failed;
    final bool needsUpload =
        document.status == VerificationDocumentStatus.needsUpload;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        if (needsUpload && hasFile)
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.upload_outlined, size: 18),
            label: const Text('Upload again'),
          )
        else if (needsUpload)
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: Text(pickLabel),
          )
        else if (hasFailed)
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          )
        else if (hasFile || isUploaded)
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: Text(changeLabel),
          )
        else
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: Text(pickLabel),
          ),
        if (hasFile || isUploaded || hasFailed)
          OutlinedButton.icon(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Remove'),
          ),
      ],
    );
  }
}
