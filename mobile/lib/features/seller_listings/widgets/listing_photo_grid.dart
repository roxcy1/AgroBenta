import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../state/listing_photo_item.dart';
import '../state/seller_listing_controller.dart';
import '../state/seller_listing_scope.dart';

/// The photo composer for a listing: a grid of thumbnail tiles plus an add tile.
///
/// Each tile shows the picked file or the served URL, a delete button, an
/// upload indicator while the batch is in flight, and move controls. The add
/// tile disables once the server's 10-photo ceiling is reached so the seller
/// can never reach a state the endpoint rejects with a 422.
class ListingPhotoGrid extends StatelessWidget {
  const ListingPhotoGrid({super.key});

  SellerListingController _controller(BuildContext context) =>
      SellerListingScope.of(context);

  @override
  Widget build(BuildContext context) {
    final SellerListingController controller = _controller(context);
    final List<ListingPhotoItem> photos = controller.photos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ...photos.asMap().entries.map<Widget>((MapEntry<int, ListingPhotoItem> entry) {
          final int index = entry.key;
          final ListingPhotoItem photo = entry.value;
          return _Tile(
            key: ValueKey<String>(photo.id),
            photo: photo,
            onRemove: () => controller.removePhotoItem(photo.id),
            onMoveUp: index > 0
                ? () => controller.reorderPhotos(index, index - 1)
                : null,
            onMoveDown: index < photos.length - 1
                ? () => controller.reorderPhotos(index, index + 1)
                : null,
          );
        }),
        if (controller.canAddPhoto)
          _AddTile(onAdd: () => _pickPhotos()),
      ],
    );
  }

  /// Opens a sheet to choose image source (gallery or camera), then appends any picks.
  Future<void> _pickPhotos() async {
    final ImagePicker picker = ImagePicker();
    final bool? cameraSelected = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add photos from'),
        content: const Text('Choose the source for your photos:'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Gallery'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Camera'),
          ),
        ],
      ),
    );
    if (cameraSelected == true) {
      final XFile? picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked != null) {
        controller.addPickedPhotos([picked]);
      }
    } else {
      final List<XFile>? picked = await picker.pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked.isNotEmpty) {
        controller.addPickedPhotos(picked);
      }
    }
  }
}

/// One photo tile: thumbnail, delete, upload indicator, and move controls.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.photo,
    required this.onRemove,
    this.onMoveUp,
    this.onMoveDown,
  });

  final ListingPhotoItem photo;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        _Thumbnail(photo: photo),
        if (photo.status == ListingPhotoStatus.uploading)
          _UploadIndicator(progress: photo.progress ?? 0.0),
        Positioned(
          right: -AppSpacing.xxs,
          top: -AppSpacing.xxs,
          child: _DeleteButton(onPressed: onRemove),
        ),
        if (onMoveUp != null)
          Positioned(
            left: -AppSpacing.xxs,
            top: -AppSpacing.xxs,
            child: _MoveButton(icon: Icons.arrow_upward, onPressed: onMoveUp),
          ),
        if (onMoveDown != null)
          Positioned(
            left: -AppSpacing.xxs,
            bottom: -AppSpacing.xxs,
            child: _MoveButton(icon: Icons.arrow_downward, onPressed: onMoveDown),
          ),
      ],
    );
  }
}

const double _tileSize = 96;

/// Renders one composer photo: served URL or locally-picked file, with a
/// placeholder fallback so a broken frame never shows (GAP-06).
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.photo});

  final ListingPhotoItem photo;

  @override
  Widget build(BuildContext context) {
    if (photo.status == ListingPhotoStatus.uploaded && photo.url != null) {
      return _NetworkImage(url: photo.url!);
    }
    if (photo.file != null) {
      return _FileImage(file: photo.file!);
    }
    return const _Placeholder(showSpinner: false);
  }
}

/// Renders a served photo URL, falling back to the placeholder on any load
/// failure so a broken frame never shows (GAP-06).
class _NetworkImage extends StatelessWidget {
  const _NetworkImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        width: _tileSize,
        height: _tileSize,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? _) =>
                const _Placeholder(showSpinner: false),
        loadingBuilder: (
          BuildContext context,
          Widget child,
          ImageChunkEvent? progress,
        ) =>
            progress == null ? child : const _Placeholder(showSpinner: true),
        excludeFromSemantics: true,
      ),
    );
  }
}

/// Renders a locally-picked file as a thumbnail.
class _FileImage extends StatelessWidget {
  const _FileImage({required this.file});

  final XFile file;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Image.file(
        File(file.path),
        fit: BoxFit.cover,
        width: _tileSize,
        height: _tileSize,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? _) =>
                const _Placeholder(showSpinner: false),
        excludeFromSemantics: true,
      ),
    );
  }
}

/// The neutral stand-in when a composer photo cannot be rendered yet.
class _Placeholder extends StatelessWidget {
  const _Placeholder({this.showSpinner = false});

  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _tileSize,
      height: _tileSize,
      color: AppColors.background,
      child: Center(
        child: showSpinner
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.image_not_supported_outlined,
                size: 20,
                color: AppColors.textSecondary,
              ),
      ),
    );
  }
}

/// An inline upload progress indicator over an in-flight tile.
class _UploadIndicator extends StatelessWidget {
  const _UploadIndicator({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: _tileSize,
      height: _tileSize,
      color: AppColors.primary.withValues(alpha: 0.15),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_upload, color: AppColors.primary, size: 20),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${(progress * 100).round()}%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The delete button on a photo tile.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.90),
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
        onPressed: onPressed,
        tooltip: 'Remove photo',
      ),
    );
  }
}

/// A move control (up or down) on a photo tile.
class _MoveButton extends StatelessWidget {
  const _MoveButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.90),
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 18, color: enabled ? AppColors.text : AppColors.textSecondary),
        onPressed: onPressed,
      ),
    );
  }
}

/// The add photo tile: a [+] that opens the gallery or camera.
class _AddTile extends StatelessWidget {
  const _AddTile({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _tileSize,
      height: _tileSize,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Material(
          color: AppColors.background,
          child: InkWell(
            onTap: onAdd,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.add_a_photo, size: 24, color: AppColors.primary),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Add photo',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


