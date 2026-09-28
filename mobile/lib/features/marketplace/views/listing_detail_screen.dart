import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/listing.dart';
import '../../../repositories/marketplace_repository.dart';
import '../state/listing_detail_controller.dart';
import '../state/listing_detail_state.dart';
import '../state/marketplace_scope.dart';
import '../widgets/listing_photo.dart';
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
      appBar: AppBar(title: const Text('Listing')),
      body: SafeArea(child: _ListingDetailBody(listingId: listingId)),
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
    final MarketplaceRepository repository = MarketplaceScope.readOf(context).repository;
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
class _DetailContent extends StatelessWidget {
  const _DetailContent({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        SizedBox(
          height: 220,
          child: ListingPhoto(listing: listing),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                listing.livestockType.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                listing.title,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.md),
              // The exact amount, to the cent. A card rounds for space; here
              // there is room, and this is the figure the buyer is deciding on.
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
              const SizedBox(height: AppSpacing.lg),
              _DetailCard(
                title: 'Details',
                rows: <_DetailRow>[
                  _DetailRow('Location', listing.location),
                  if (listing.ageLabel != null)
                    _DetailRow('Age', listing.ageLabel!),
                  if (listing.weightLabel != null)
                    _DetailRow('Weight', listing.weightLabel!),
                  if (listing.gender != null)
                    _DetailRow('Gender', _titleCase(listing.gender!)),
                  if (listing.healthStatus != null)
                    _DetailRow('Health', listing.healthStatus!),
                  if (listing.vaccination != null)
                    _DetailRow('Vaccination', listing.vaccination!),
                ],
              ),
              if (listing.shortDescription.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                _DetailCard(
                  title: 'Description',
                  rows: <_DetailRow>[
                    _DetailRow.body(listing.shortDescription),
                  ],
                ),
              ],
              if (listing.additionalNotes != null &&
                  listing.additionalNotes!.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                _DetailCard(
                  title: 'Seller’s notes',
                  rows: <_DetailRow>[
                    _DetailRow.body(listing.additionalNotes!),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _DetailCard(
                title: 'Seller',
                rows: <_DetailRow>[_DetailRow('Name', listing.seller.name)],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.schedule_outlined,
                    size: 14,
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
        ),
      ],
    );
  }
}

/// A titled group of rows.
///
/// Rows whose value is absent are omitted by the caller rather than rendered
/// as a dash, so an unrecorded field does not look like a recorded "none".
class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.rows});

  final String title;
  final List<_DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            for (final _DetailRow row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: row.build(context),
              ),
          ],
        ),
      ),
    );
  }
}

/// One label-value pair, or a paragraph when no label is given.
class _DetailRow {
  const _DetailRow(this.label, [this.value]) : body = null;

  const _DetailRow.body(String this.body) : label = null, value = null;

  final String? label;
  final String? value;

  /// Paragraph form, for description and notes.
  final String? body;

  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? paragraph = body;

    if (paragraph != null) {
      return Text(paragraph, style: theme.textTheme.bodyMedium);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label!,
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(value!, style: theme.textTheme.bodyLarge),
      ],
    );
  }
}

/// Shown when the listing is not available to this buyer.
///
/// Fixed copy, no server string. A `404` here means the listing is not
/// visible — and by [D-02] the server will not say whether it is draft, sold,
/// owned by someone else, or simply does not exist. The app must not guess at
/// that either, because "this listing was removed" and "you do not have access"
/// mean different things to a buyer and the backend has declined to be the one
/// that tells them apart.
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

/// Capitalises the first letter of a lowercase API value.
String _titleCase(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
}
