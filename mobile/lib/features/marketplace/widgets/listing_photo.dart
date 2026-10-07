import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/listing.dart';

/// A listing photo, or an honest placeholder when there is not one to show.
///
/// ## Why this widget is mostly a placeholder
///
/// `listings.photos` is a JSON column and `MobileListingResource` now returns
/// its contents as a flat list of strings. That is all it returns: there is no
/// upload endpoint, no storage disk bound to the column, and no agreed URL
/// scheme (**OQ-09** / **D-10**), so the values in flight are storage-relative
/// paths such as `listings/1/front.jpg` rather than anything fetchable.
///
/// This widget therefore draws a network image **only** when the stored value is
/// already an absolute `http`/`https` URL — the case where it is genuinely
/// usable as-is. Everything else gets a neutral placeholder.
///
/// The temptation here is to prefix a base URL or a `/storage/` segment. That
/// would be inventing a storage mechanism this phase is not permitted to create
/// (functional documentation §4.5), and it fails in the worst way: a URL that
/// looks valid, 404s, and reads as a bug to a buyer. A calm placeholder is the
/// better failure.
///
/// When a photo URL scheme *is* decided, the only change needed is in
/// [Listing.isDirectlyLoadablePhotoUrl] — nothing here has to learn about it.
class ListingPhoto extends StatelessWidget {
  const ListingPhoto({
    required this.listing,
    this.height,
    this.width,
    super.key,
  });

  /// The listing whose first usable photo is shown, if any.
  final Listing listing;

  /// Fixed height, for a card thumbnail or a detail banner.
  final double? height;

  /// Fixed width. Omit to fill the available width.
  final double? width;

  /// The first photo the client can actually fetch, or `null`.
  String? get _loadableUrl {
    for (final String path in listing.photos) {
      if (Listing.isDirectlyLoadablePhotoUrl(path)) {
        return path.trim();
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final String? url = _loadableUrl;

    return SizedBox(
      height: height,
      width: width,
      child: url == null
          ? _Placeholder(hasPhotos: listing.photos.isNotEmpty)
          : Image.network(
              url,
              fit: BoxFit.cover,
              height: height,
              width: width,
              // A failed load must not leave a broken-image glyph. Falling back
              // to the same placeholder is indistinguishable from "no photo",
              // which is the truth from the buyer's point of view.
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? _) =>
                      _Placeholder(hasPhotos: true),
              loadingBuilder:
                  (
                    BuildContext context,
                    Widget child,
                    ImageChunkEvent? progress,
                  ) => progress == null
                  ? child
                  : _Placeholder(hasPhotos: true, showSpinner: true),
              // A decorative, redundant image: the livestock type and breed are
              // already rendered as text beside it, so announcing the picture
              // too would just repeat them to a screen reader.
              excludeFromSemantics: true,
            ),
    );
  }
}

/// The neutral stand-in for a listing with no displayable photo.
///
/// One idea, no illustration, no emoji — `mobile/DESIGN.md` §11 rules out both
/// decorative illustrations and emoji as interface elements, and a livestock
/// glyph is arguably a small illustration. A muted icon plus a short label says
/// "no photo" in words as well as shape, so the state does not depend on
/// recognising the icon.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.hasPhotos, this.showSpinner = false});

  /// Whether photos exist but cannot be displayed, as opposed to there being
  /// none at all. Changes the label so the two are not conflated.
  final bool hasPhotos;

  /// Shows a small progress indicator while the image loads.
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
      ),
      child: Center(
        child: showSpinner
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.image_not_supported_outlined,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      hasPhotos ? 'Photo unavailable' : 'No photo',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
