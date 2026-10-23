import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/listing.dart';
import '../../../models/message.dart';
import '../../../models/transaction.dart';
import '../../../repositories/marketplace_repository.dart';
import '../../../repositories/transaction_repository.dart';
import '../../../widgets/detail_row.dart';
import '../../auth/state/auth_scope.dart';
import '../../inquiries/view/inquire_screen.dart';
import '../../messaging/view/chat_screen.dart';
import '../../transactions/state/transaction_scope.dart';
import '../../transactions/views/transaction_detail_screen.dart';
import '../../transactions/widgets/buy_sheet.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Listing Details')),
      // The gallery deliberately runs under the app bar's lower edge, so the
      // top inset is not reserved here; the bottom inset is, so the pinned
      // action bar clears the system navigation area.
      body: SafeArea(top: false, child: _ListingDetailBody(listingId: listingId)),
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
  static const double _panelOverlap = 16;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            child: Stack(
              children: <Widget>[
                ListingPhotoCarousel(
                  listing: listing,
                  height: _galleryHeight,
                ),
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

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
        border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SummarySection(listing: listing),
          const _PanelDivider(),
          _AttributesSection(listing: listing),
          if (listing.healthStatus != null || listing.vaccination != null) ...<Widget>[
            const _PanelDivider(),
            _FactsSection(listing: listing),
          ],
          if (listing.shortDescription.trim().isNotEmpty) ...<Widget>[
            const _PanelDivider(),
            _TextSection(
              title: 'Description',
              body: listing.shortDescription,
            ),
          ],
          if (additionalNotes != null && additionalNotes.trim().isNotEmpty) ...<Widget>[
            const _PanelDivider(),
            _TextSection(title: 'Seller’s notes', body: additionalNotes),
          ],
          const _PanelDivider(),
          _SellerSection(listing: listing),
        ],
      ),
    );
  }
}

class _PanelDivider extends StatelessWidget {
  const _PanelDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: AppColors.border);
}

/// Type, title, price, availability and location — the top of the panel.
class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.lg,
        AppSpacing.screenGutter,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            listing.livestockType.toUpperCase(),
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(listing.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          // The exact amount, to the cent. A card rounds for space; here there
          // is room, and this is the figure the buyer is deciding on.
          Text(
            AppFormatters.formatMoney(listing.askingPrice) ??
                listing.askingPrice,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: AppColors.primary,
            ),
          ),
          if (listing.quantity > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${listing.quantity} '
              '${listing.quantity == 1 ? 'head' : 'heads'} available',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (listing.location.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    listing.location,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Age, Weight and Gender across three columns with hairline separators.
///
/// Every column is shown; a value the API did not supply renders as an em dash
/// rather than being invented.
class _AttributesSection extends StatelessWidget {
  const _AttributesSection({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.md,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _Attribute(label: 'Age', value: listing.ageLabel),
            ),
            const _AttributeSeparator(),
            Expanded(
              child: _Attribute(label: 'Weight', value: listing.weightLabel),
            ),
            const _AttributeSeparator(),
            Expanded(
              child: _Attribute(label: 'Gender', value: listing.genderLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _Attribute extends StatelessWidget {
  const _Attribute({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? value = this.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value ?? '—',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: value == null ? AppColors.textSecondary : AppColors.text,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _AttributeSeparator extends StatelessWidget {
  const _AttributeSeparator();

  @override
  Widget build(BuildContext context) => const VerticalDivider(
        width: AppSpacing.md,
        thickness: 1,
        color: AppColors.border,
      );
}

/// Health and vaccination, when the listing records them.
///
/// Not part of the three-column attribute row, but kept so the screen does not
/// silently lose data the API supplies.
class _FactsSection extends StatelessWidget {
  const _FactsSection({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final String? healthStatus = listing.healthStatus;
    final String? vaccination = listing.vaccination;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (healthStatus != null)
            DetailRow(label: 'Health', value: healthStatus),
          if (vaccination != null)
            DetailRow(label: 'Vaccination', value: vaccination),
        ],
      ),
    );
  }
}

/// A titled block of prose — the description or the seller's notes.
class _TextSection extends StatelessWidget {
  const _TextSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          DetailRow.body(body),
        ],
      ),
    );
  }
}

/// Who is selling, reduced to what the marketplace API discloses.
///
/// The seller projection is `{ id, name }` — no avatar, no verification flag,
/// no email — so this shows an initials avatar and the name, and does not
/// imply a "Verified Seller" badge the API never sends.
class _SellerSection extends StatelessWidget {
  const _SellerSection({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Seller', style: theme.textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primarySurface,
                child: Text(
                  _initial(listing.seller.name),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  listing.seller.name,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              const Icon(
                Icons.schedule_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  'Posted ${AppFormatters.formatRelative(listing.createdAt)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The pinned Message / Inquire / Buy bar.
///
/// Three separate paths, because they are three separate things: a free-form
/// chat thread, the structured inquiry form, and transaction creation. The
/// middle one used to open the Buy sheet, which left a button labelled
/// "Inquire" creating a transaction — a buyer who wanted to *ask* something
/// could not, and a buyer who wanted to buy was taken to a sheet they did not
/// ask for. Each button now does what it says.
///
/// The labels are text-only on purpose: three icon-plus-label buttons overflow
/// on a 320dp phone once each button's padding is counted, and the label is
/// the part that carries the meaning (mobile/DESIGN.md: the word, not the
/// decoration).
///
/// Renders nothing when the viewer owns the listing — a seller has no create
/// endpoint, cannot transact with themselves (§6.2), and cannot message
/// themselves either.
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
              onPressed: viewerId == null
                  ? null
                  : () => _openThread(context, viewerId),
              child: const Text('Message'),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: FilledButton(
              style: _barButtonStyle,
              onPressed: () => _openInquiry(context),
              child: const Text('Inquire'),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: OutlinedButton(
              style: _barButtonStyle,
              onPressed: () => _openBuy(context),
              child: const Text('Buy'),
            ),
          ),
        ],
      ),
    );
  }

  /// Tighter horizontal padding so all three labels fit at the narrowest
  /// widths the app supports, without shrinking the touch target's height.
  /// Shared by all three buttons, so the row stays even.
  static final ButtonStyle _barButtonStyle = ButtonStyle(
    padding: WidgetStatePropertyAll<EdgeInsets>(
      const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    ),
  );

  /// Opens the existing chat thread with the seller, tied to this listing.
  ///
  /// `MessagingScope` is read by [ChatScreen] in its own `initState`, not here:
  /// this screen must build without a messaging scope so the marketplace tests
  /// that mount it do not need one.
  void _openThread(BuildContext context, int viewerId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ChatScreen(
          counterpart: ChatUser(
            id: listing.seller.id,
            name: listing.seller.name,
            avatarUrl: null,
          ),
          currentUserId: viewerId,
          listingId: listing.id,
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

  /// Opens the existing Buy sheet and, on success, the created transaction.
  /// The sheet is the single create path; this button only opens it.
  Future<void> _openBuy(BuildContext context) async {
    final TransactionRepository repository = TransactionScope.readOf(context);
    final Transaction? created = await BuySheet.show(
      context,
      listing: listing,
      repository: repository,
    );
    if (created != null && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              TransactionDetailScreen(transactionId: created.id),
        ),
      );
    }
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

/// The fallback avatar letter for a seller with no image.
String _initial(String name) {
  final String trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
}
