import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../widgets/initials_avatar.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/listing.dart';
import '../../../models/message.dart';
import '../../../repositories/marketplace_repository.dart';
import '../../../widgets/detail_row.dart';
import '../../auth/state/auth_scope.dart';
import '../../inquiries/view/inquire_screen.dart';
import '../../messaging/view/chat_screen.dart';
import '../state/listing_detail_controller.dart';
import '../state/listing_detail_state.dart';
import '../state/marketplace_scope.dart';
import '../widgets/listing_photo_carousel.dart';
import '../widgets/marketplace_state_views.dart';

/// One listing's detail, from `GET /listings/{listing}`.
///
/// Takes an [listingId] and nothing else. The list object is deliberately not
/// passed in, even though the caller has one: the whole point of re-fetching is
/// that a listing may have become unavailable since it was listed, and seeding
/// the screen with the list copy would show stale data for a moment and leave
/// the screen unable to tell whether what it is displaying is still valid.
class ListingDetailScreen extends StatelessWidget {
  const ListingDetailScreen({required this.listingId, super.key});

  final int listingId;

  @override
  Widget build(BuildContext context) {
    // No app bar: the photo runs to the top of the screen and a round back
    // button floats over it, as in the approved design. The bottom inset is
    // reserved so the pinned action bar clears the system navigation area.
    return Scaffold(
      body: Stack(
        children: <Widget>[
          SafeArea(top: false, child: _ListingDetailBody(listingId: listingId)),
          Positioned(
            top: MediaQuery.paddingOf(context).top + AppSpacing.xs,
            left: AppSpacing.sm,
            child: const _FloatingBackButton(),
          ),
        ],
      ),
    );
  }
}

class _ListingDetailBody extends StatefulWidget {
  const _ListingDetailBody({required this.listingId});

  final int listingId;

  @override
  State<_ListingDetailBody> createState() => _ListingDetailBodyState();
}

class _ListingDetailBodyState extends State<_ListingDetailBody> {
  late final ListingDetailController _controller;

  @override
  void initState() {
    super.initState();
    // Read from `initState`, so no dependency is registered: this screen cares
    // about the repository's identity, which never changes, and not about the
    // list controller's state. The screen is pushed above the shell but still
    // under the `MarketplaceScope` that `main.dart` installs, so the lookup
    // resolves the same way it would from the list.
    final MarketplaceRepository repository = MarketplaceScope.readOf(
      context,
    ).repository;
    _controller = ListingDetailController(repository, widget.listingId);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? child) {
        final ListingDetailState state = _controller.state;

        if (state.isLoading) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: AppSpacing.md),
                Text('Loading listing'),
              ],
            ),
          );
        }

        if (state.isUnavailable) {
          return const _UnavailableNotice();
        }

        if (state.status == ListingDetailStatus.failed) {
          return MarketplaceErrorState(
            message: state.errorMessage ?? 'Something went wrong.',
            onRetry: _controller.load,
          );
        }

        final Listing? listing = state.listing;
        if (listing == null) {
          // `initial` or a state with no listing. Reachable for a frame between
          // construction and the first `loading` publish, so it needs a
          // non-crashing answer.
          return const SizedBox.shrink();
        }

        return _DetailContent(listing: listing);
      },
    );
  }
}

/// What the detail screen shows once the listing is confirmed available.
///
/// A gallery with a white details panel overlapping its lower edge, and a
/// pinned action bar below the scroll so Message / Inquire / Buy stay
/// reachable however long the description runs.
class _DetailContent extends StatelessWidget {
  const _DetailContent({required this.listing});

  final Listing listing;

  /// Gallery height. Fixed so the amount the panel overlaps is predictable.
  static const double _galleryHeight = 260;

  /// How far the details panel rides up over the gallery's lower edge.
  static const double _panelOverlap = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            child: Stack(
              children: <Widget>[
                ListingPhotoCarousel(listing: listing, height: _galleryHeight),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Transparent spacer: the panel begins this far down, so it
                    // overhangs the last `_panelOverlap` pixels of the gallery.
                    SizedBox(height: _galleryHeight - _panelOverlap),
                    _DetailsPanel(listing: listing),
                  ],
                ),
              ],
            ),
          ),
        ),
        _ActionBar(listing: listing),
      ],
    );
  }
}

/// The white panel that overlaps the gallery and holds every text section.
///
/// Sections are separated by hairline dividers (DESIGN: prefer borders over
/// shadows) and the panel itself is a single rounded-top surface so the
/// overlap reads as one card rather than a stack of cards.
class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final String? additionalNotes = listing.additionalNotes;

    return ColoredBox(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.md,
          AppSpacing.screenGutter,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _SummarySection(listing: listing),
            const SizedBox(height: AppSpacing.md),
            _FactsGrid(listing: listing),
            if (listing.hasEstimatedMeasurement) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Estimated age or weight is provided by the seller and is not '
                'independently verified.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (listing.shortDescription.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              _TextSection(
                title: 'Description',
                body: listing.shortDescription,
              ),
            ],
            if (additionalNotes != null &&
                additionalNotes.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              _TextSection(title: 'Seller’s notes', body: additionalNotes),
            ],
            const SizedBox(height: AppSpacing.lg),
            _SellerSection(listing: listing),
          ],
        ),
      ),
    );
  }
}

/// Name, where and when, then the price — the figure the buyer decides on.
class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String type = listing.livestockType.trim();
    final String species = type.isEmpty
        ? ''
        : '${type[0].toUpperCase()}${type.substring(1)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (species.isNotEmpty)
          Text(species, style: theme.textTheme.labelMedium),
        Text(listing.title, style: theme.textTheme.headlineSmall),
        if (listing.location.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: <Widget>[
              const Icon(
                Icons.location_on_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(listing.location, style: theme.textTheme.bodySmall),
              ),
              Text(
                ' · Posted ${AppFormatters.formatRelative(listing.createdAt)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        // The exact amount, to the cent. A card rounds for space; here there
        // is room, and this is the figure the buyer is deciding on.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(
                AppFormatters.formatMoney(listing.askingPrice) ??
                    listing.askingPrice,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: AppColors.primary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text('per head', style: theme.textTheme.labelMedium),
          ],
        ),
      ],
    );
  }
}

/// Six facts in a bordered three-column grid: Age, Weight, Gender, Health,
/// Vaccination and Quantity. A missing fact shows a dash rather than hiding,
/// so the grid keeps its shape.
class _FactsGrid extends StatelessWidget {
  const _FactsGrid({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final List<(String, String?)> facts = <(String, String?)>[
      // "Estimated Age" / "Measured Weight" when the seller said which.
      (listing.ageInformationLabel ?? 'Age', listing.ageLabel),
      (listing.weightInformationLabel ?? 'Weight', listing.weightLabel),
      ('Gender', listing.genderLabel),
      ('Health', listing.healthStatus),
      ('Vaccination', listing.vaccination),
      (
        'Available',
        (listing.availableQuantity ?? listing.quantity) > 0
            ? '${listing.availableQuantity ?? listing.quantity} ${(listing.availableQuantity ?? listing.quantity) == 1 ? 'head' : 'heads'}'
            : null,
      ),
    ];

    Widget row(int from) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = from; i < from + 3; i++) ...<Widget>[
            if (i > from)
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: AppColors.border,
              ),
            Expanded(
              child: _Fact(label: facts[i].$1, value: facts[i].$2),
            ),
          ],
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: <Widget>[
          row(0),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          row(3),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? value = this.value;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xxxs),
          Text(
            value ?? '—',
            style: theme.textTheme.titleSmall?.copyWith(
              color: value == null ? AppColors.textSecondary : AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextSection extends StatelessWidget {
  const _TextSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        DetailRow.body(body),
      ],
    );
  }
}

/// The seller, as one bordered row.
class _SellerSection extends StatelessWidget {
  const _SellerSection({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: <Widget>[
          InitialsAvatar(name: listing.seller.name, radius: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Seller', style: theme.textTheme.labelSmall),
                Text(
                  listing.seller.name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The pinned Ask Seller / I'm Interested bar.
///
/// Two separate paths: **Ask Seller** opens the existing buyer–seller
/// conversation without creating an inquiry, offer, transaction or
/// reservation; **I'm Interested** opens the existing structured inquiry form.
///
/// The thread is loaded as the full buyer–seller conversation, while a new
/// message started here is tagged with this listing. That keeps replies the
/// seller sent from the normal Messages inbox visible instead of hiding them
/// behind a listing filter.
///
/// Renders nothing when the viewer owns the listing — a seller cannot message
/// or inquire with themselves.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final int? viewerId = AuthScope.of(context).state.user?.id;
    if (viewerId != null && viewerId == listing.seller.id) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton(
              style: _barButtonStyle,
              onPressed: () => _openMessages(context, viewerId),
              child: const Text('Ask Seller'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FilledButton(
              style: _barButtonStyle,
              onPressed: () => _openInquiry(context),
              child: const Text('I\'m Interested'),
            ),
          ),
        ],
      ),
    );
  }

  /// Tighter horizontal padding so the single button fits at the narrowest
  /// widths the app supports, without shrinking the touch target's height.
  static final ButtonStyle _barButtonStyle = ButtonStyle(
    padding: WidgetStatePropertyAll<EdgeInsets>(
      const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    ),
  );

  /// Opens the existing conversation with the listing's seller.
  ///
  /// Nothing is created until the buyer actually sends a message. The thread is
  /// not narrowed to this listing, so prior buyer–seller history remains
  /// visible; a new message sent here carries the listing id.
  void _openMessages(BuildContext context, int? viewerId) {
    if (viewerId == null) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ChatScreen(
          counterpart: ChatUser(
            id: listing.seller.id,
            name: listing.seller.name,
            avatarUrl: null,
          ),
          currentUserId: viewerId,
          messageListingId: listing.id,
          counterpartRole: 'Seller',
        ),
      ),
    );
  }

  /// Opens the structured inquiry form with the listing it asks about.
  ///
  /// The screen needs no result handling: it renders its own confirmation once
  /// the server confirms, and pops back here on Done or the back arrow.
  void _openInquiry(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => InquireScreen(listing: listing),
      ),
    );
  }
}

/// What the detail screen shows when the listing is not visible to the caller.
class _UnavailableNotice extends StatelessWidget {
  const _UnavailableNotice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.visibility_off_outlined,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'This listing is no longer available',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'It may have been sold or withdrawn, or it may never have been '
              'visible to you.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back to listings'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The round white back button that sits on top of the photo.
class _FloatingBackButton extends StatelessWidget {
  const _FloatingBackButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.94),
      shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back, color: AppColors.text),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
