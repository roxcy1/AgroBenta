import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/listing.dart';

/// A swipeable carousel over a listing's full photo set.
///
/// Every index obeys the GAP-06 rule: render a placeholder for any
/// non-http(s) value, and render a placeholder for an empty set — never a
/// broken frame and never a crash.
class ListingPhotoCarousel extends StatefulWidget {
  const ListingPhotoCarousel({required this.listing, this.height = 220, super.key});

  final Listing listing;
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

    if (photos.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const _CarouselPlaceholder(hasPhotos: false),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _pageController,
            itemCount: photos.length,
            onPageChanged: (int page) => setState(() => _page = page),
            itemBuilder: (BuildContext context, int index) {
              final String photo = photos[index];
              return _CarouselPhoto(url: photo);
            },
          ),
        ),
        if (photos.length > 1) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              ...photos.asMap().entries.map<Widget>((entry) {
                final int i = entry.key;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                  width: _page == i ? 10 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _page == i
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                );
              }),
            ],
          ),
        ],
      ],
    );
  }
}

/// One carousel page: a photo URL or a placeholder.
class _CarouselPhoto extends StatelessWidget {
  const _CarouselPhoto({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final Uri? uri = Uri.tryParse(url.trim());
    final bool loadable =
        uri != null && uri.hasScheme && uri.host.isNotEmpty && (uri.scheme == 'http' || uri.scheme == 'https');

    if (!loadable) {
      return const _CarouselPlaceholder(hasPhotos: true);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Image.network(
        url.trim(),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? _) =>
                const _CarouselPlaceholder(hasPhotos: true),
        loadingBuilder: (
          BuildContext context,
          Widget child,
          ImageChunkEvent? progress,
        ) =>
            progress == null ? child : const _CarouselPlaceholder(hasPhotos: true, showSpinner: true),
        excludeFromSemantics: true,
      ),
    );
  }
}

/// Placeholder inside the carousel.
class _CarouselPlaceholder extends StatelessWidget {
  const _CarouselPlaceholder({this.hasPhotos = false, this.showSpinner = false});

  final bool hasPhotos;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  Icon(
                    Icons.image_not_supported_outlined,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    hasPhotos ? 'Photo unavailable' : 'No photo',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
      ),
    );
  }
}
