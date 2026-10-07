import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/listing.dart';
import '../state/seller_listing_controller.dart';
import '../state/seller_listing_scope.dart';
import '../state/seller_listing_state.dart';
import 'seller_listing_form_screen.dart';
import 'seller_listing_views.dart';
import '../../../widgets/detail_row.dart';
import '../../../widgets/section_card.dart';

/// One of the seller's own listings, in full, with its available actions.
///
/// The seller's own view of a record, not the buyer's: the status and what it
/// means are stated at the top, and the actions the server will accept are the
/// whole of the bottom. A seller opening a `pending` listing is looking for the
/// answer "is it approved yet, and can I do anything about it", and that answer is
/// on this screen rather than two taps away.
///
/// Takes the listing as it was handed in and re-reads the list behind it. There
/// is no seller-facing detail endpoint — the route is deliberately absent from
/// the contract, and adding one to a screen would be inventing an API — so the
/// screen is told which listing it is showing and stays consistent by
/// re-querying the list the controller already owns.
class SellerListingDetailScreen extends StatefulWidget {
  const SellerListingDetailScreen({required this.listing, super.key});

  /// The listing to display. May be a snapshot older than the server's copy.
  final Listing listing;

  @override
  State<SellerListingDetailScreen> createState() =>
      _SellerListingDetailScreenState();
}

class _SellerListingDetailScreenState extends State<SellerListingDetailScreen> {
  late final SellerListingController _controller;

  /// The newest copy of the listing this screen knows about.
  ///
  /// Starts as the snapshot it was given and is replaced whenever the list
  /// contains a newer record with the same id. A snapshot rather than a single
  /// read: the list is the only source of truth this feature has, and it is
  /// re-read after every action.
  late Listing _listing;

  @override
  void initState() {
    super.initState();
    _controller = SellerListingScope.readOf(context);
    _listing = widget.listing;
    // After the current frame, not during it: `loadInitial` notifies
    // synchronously, and this route is built on its way onto the navigator while
    // the list screen's `ListenableBuilder` is still mounted. Notifying it
    // mid-build is exactly the "setState() called during build" exception the
    // post-frame callback exists to avoid.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.loadInitial();
      }
    });
  }

  /// The listing as the list currently holds it, or the snapshot if it is not
  /// there — which happens legitimately once a listing has been deleted.
  Listing _current() {
    for (final Listing listing in _controller.state.listings) {
      if (listing.id == _listing.id) {
        return listing;
      }
    }
    return _listing;
  }

  Future<void> _edit() async {
    final Listing? updated = await Navigator.of(context).push<Listing>(
      MaterialPageRoute<Listing>(
        builder: (BuildContext context) =>
            SellerListingFormScreen(listing: _current()),
        fullscreenDialog: true,
      ),
    );

    if (!mounted || updated == null) {
      return;
    }
    // The controller already merged the update into the list; this makes the
    // screen reflect it immediately rather than waiting for a rebuild driven by
    // something else.
    setState(() => _listing = updated);
  }

  Future<void> _submit() async {
    final Listing? submitted = await _controller.submit(_listing.id);
    if (!mounted || submitted == null) {
      return;
    }
    setState(() => _listing = submitted);
  }

  Future<void> _delete() async {
    final Listing current = _current();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete this listing?'),
        content: Text(
          '"${current.title}" will be removed permanently. This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final bool deleted = await _controller.delete(current.id);
    if (!mounted) {
      return;
    }
    if (deleted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listing'),
        actions: <Widget>[
          ListenableBuilder(
            listenable: _controller,
            builder: (BuildContext context, Widget? child) {
              final Listing listing = _current();
              if (!SellerListingController.canEdit(listing)) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit listing',
                onPressed: _edit,
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? child) {
          final Listing listing = _current();
          final SellerListingState state = _controller.state;
          final bool busy =
              state.isActioning && state.actionListingId == listing.id;

          return SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.screenGutter),
                    children: <Widget>[
                      _StatusPanel(
                        listing: listing,
                        message: state.actionMessage,
                        conflict: state.conflictMessage,
                        error: state.actionErrorMessage,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SectionCard(
                        title: 'Listing',
                        children: <Widget>[
                          DetailRow(
                            label: 'Type',
                            value: listing.livestockType,
                          ),
                          if (listing.breed.trim().isNotEmpty)
                            DetailRow(label: 'Breed', value: listing.breed),
                          DetailRow(
                            label: 'Quantity',
                            value:
                                '${listing.quantity} ${listing.quantity == 1 ? 'head' : 'heads'}',
                          ),
                          if (listing.ageLabel != null)
                            DetailRow(label: 'Age', value: listing.ageLabel!),
                          if (listing.gender != null)
                            DetailRow(label: 'Gender', value: listing.gender!),
                          if (listing.weightLabel != null)
                            DetailRow(
                              label: 'Weight',
                              value: listing.weightLabel!,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SectionCard(
                        title: 'Price and location',
                        children: <Widget>[
                          DetailRow(
                            label: 'Asking price',
                            value:
                                AppFormatters.formatMoney(
                                  listing.askingPrice,
                                ) ??
                                listing.askingPrice,
                          ),
                          DetailRow(
                            label: 'Location',
                            value: listing.location,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SectionCard(
                        title: 'Details',
                        children: <Widget>[
                          if (listing.shortDescription.trim().isNotEmpty)
                            DetailRow(
                              label: 'Description',
                              value: listing.shortDescription,
                            ),
                          if (listing.healthStatus != null &&
                              listing.healthStatus!.trim().isNotEmpty)
                            DetailRow(
                              label: 'Health',
                              value: listing.healthStatus!,
                            ),
                          if (listing.vaccination != null &&
                              listing.vaccination!.trim().isNotEmpty)
                            DetailRow(
                              label: 'Vaccination',
                              value: listing.vaccination!,
                            ),
                          if (listing.additionalNotes != null &&
                              listing.additionalNotes!.trim().isNotEmpty)
                            DetailRow(
                              label: 'Notes',
                              value: listing.additionalNotes!,
                            ),
                          if (listing.shortDescription.trim().isEmpty &&
                              (listing.healthStatus == null ||
                                  listing.healthStatus!.trim().isEmpty) &&
                              (listing.vaccination == null ||
                                  listing.vaccination!.trim().isEmpty) &&
                              (listing.additionalNotes == null ||
                                  listing.additionalNotes!.trim().isEmpty))
                            Text(
                              'No further details recorded.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (listing.createdAt != null)
                        Text(
                          'Created '
                          '${AppFormatters.formatDateTime(listing.createdAt!)}'
                          '${listing.updatedAt != null ? ' · updated ${AppFormatters.formatDateTime(listing.updatedAt!)}' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                _ActionBar(
                  listing: listing,
                  busy: busy,
                  onSubmit: _submit,
                  onDelete: _delete,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The status, what it means, and any message from the last action.
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.listing,
    required this.message,
    required this.conflict,
    required this.error,
  });

  final Listing listing;
  final String? message;
  final String? conflict;
  final String? error;

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
                ListingStatusChip(status: listing.status),
                const Spacer(),
                if (listing.photos.isEmpty)
                  Text(
                    'No photos',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              listingStatusExplanation(listing.status),
              style: theme.textTheme.bodyMedium,
            ),
            if (conflict != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              ListingConflictNotice(message: conflict!),
            ],
            if (error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              ListingActionErrorBanner(message: error!),
            ],
            if (message != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(message!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// The actions available on this listing, pinned to the bottom of the screen.
///
/// Bottom rather than in the app bar, and pinned rather than at the end of the
/// scroll: a seller who has scrolled to the bottom of a long notes field should
/// not have to scroll back up to submit or delete. The app bar carries Edit
/// alone, because that one is a modification rather than a decision.
///
/// A listing with no available action shows the reason instead of a row of
/// disabled buttons. There is a difference between "you may not" and "there is
/// nothing to do yet", and a greyed-out button does not tell the user which one
/// they are looking at.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.listing,
    required this.busy,
    required this.onSubmit,
    required this.onDelete,
  });

  final Listing listing;
  final bool busy;
  final VoidCallback onSubmit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final bool canSubmit = SellerListingController.canSubmit(listing);
    final bool canDelete = SellerListingController.canDelete(listing);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: switch ((canSubmit, canDelete)) {
            (true, true) => Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onDelete,
                    child: const Text('Delete'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: busy ? null : onSubmit,
                    child: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Submit for review'),
                  ),
                ),
              ],
            ),
            (true, false) => FilledButton(
              onPressed: busy ? null : onSubmit,
              child: const Text('Submit for review'),
            ),
            (false, true) => OutlinedButton(
              onPressed: busy ? null : onDelete,
              child: const Text('Delete listing'),
            ),
            // Neither. A `pending` listing is in an administrator's queue, a
            // `sold` one is a record. Either way the seller has nothing to do,
            // and the panel above already says so.
            (false, false) => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}
