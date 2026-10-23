import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/listing.dart';

/// A swipeable gallery of a listing's real photo set.
///
/// Rendered as a fixed-height, full-bleed image area rather than an inset card:
/// the detail screen's white details panel overlaps its lower edge, so the
/// gallery has to reach the screen edges and sit behind that panel.
///
/// ## The photo rule
///
/// Every index obeys the same rule as `ListingPhoto`: only a value that is
/// already an absolute `http`/`https` URL is handed to `Image.network`; an
/// empty set, a storage-relative path and a failed load all get the same
/// neutral placeholder. See `Listing.isDirectlyLoadablePhotoUrl`. Never
/// synthesise a base URL here.
///
/// Page indicators are drawn **over** the lower edge of the image and appear
/// only when there is more than one photo — a single-image listing has nothing
/// to page between, and showing "1 of 1" would be noise.
class ListingPhotoCarousel extends StatefulWidget {
  const ListingPhotoCarousel({
    required this.listing,
    this.height = 240,
    super.key,
  });

  final Listing listing;

  /// Fixed gallery height. The detail screen sets its own so the overlap with
  /// the details panel is predictable.
  final double height;

  @override
  State<ListingPhotoCarousel> createState() => _ListingPhotoCarouselState();
}

class _ListingPhotoCarouselState extends State<ListingPhotoCarousel> {
  final PageController _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> photos = widget.listing.photos;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (photos.isEmpty)
            const _GalleryPlaceholder(hasPhotos: false)
          else
            PageView.builder(
              controller: _pageController,
              itemCount: photos.length,
              onPageChanged: (int page) => setState(() => _page = page),
              itemBuilder: (BuildContext context, int index) =>
                  _GalleryPhoto(url: photos[index]),
            ),
          if (photos.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: AppSpacing.lg,
              child: _PageIndicators(count: photos.length, current: _page),
            ),
        ],
      ),
    );
  }
}

/// One gallery page, or the placeholder when the value is not fetchable.
class _GalleryPhoto extends StatelessWidget {
  const _GalleryPhoto({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (!Listing.isDirectlyLoadablePhotoUrl(url)) {
      return const _GalleryPlaceholder(hasPhotos: true);
    }

    return Image.network(
      url.trim(),
      fit: BoxFit.cover,
      width: double.infinity,
      // A failed load falls back to the same placeholder as "no photo": from
      // the buyer's point of view the photo is simply not there.
      errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
          const _GalleryPlaceholder(hasPhotos: true),
      loadingBuilder: (
        BuildContext context,
        Widget child,
        ImageChunkEvent? progress,
      ) =>
          progress == null
              ? child
              : const _GalleryPlaceholder(hasPhotos: true, showSpinner: true),
      excludeFromSemantics: true,
    );
  }
}

/// The dots over the lower edge of the gallery.
///
/// Sits on a translucent scrim so it stays legible over any photo, and carries
/// a `Semantics` label because a row of dots conveys nothing to a screen
/// reader on its own.
class _PageIndicators extends StatelessWidget {
  const _PageIndicators({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Image ${current + 1} of $count',
      child: Align(
        alignment: Alignment.center,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < count; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: current == i ? 9 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: current == i
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The neutral branded placeholder for a gallery with nothing to show.
///
/// No emoji and no illustration — the same rule the card's placeholder follows.
/// A calm surface with an icon and a short label is the honest failure.
class _GalleryPlaceholder extends StatelessWidget {
  const _GalleryPlaceholder({required this.hasPhotos, this.showSpinner = false});

  /// Whether photos exist but cannot be displayed, as opposed to there being
  /// none at all. Changes the label so the two are not conflated.
  final bool hasPhotos;

  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: showSpinner
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.image_not_supported_outlined,
                    size: 28,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    hasPhotos ? 'Photo unavailable' : 'No photo',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
      ),
    );
  }
}
