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
import '../../marketplace/widgets/listing_photo_carousel.dart';
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
    final Listing current = _current();
    if (!SellerListingController.canSubmit(current) ||
        !SellerListingController.hasSubmissionPhotos(current)) {
      return;
    }
    final Listing? submitted = await _controller.submit(current.id);
    if (!mounted || submitted == null) {
      return;
    }
    setState(() => _listing = submitted);
  }

  Future<void> _markSold() async {
    final Listing current = _current();
    if (!SellerListingController.canMarkSold(current)) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Mark this listing as sold?'),
        content: const Text(
          'The sale is complete. This listing will stay on your record as sold '
          'and can no longer be edited or deleted. It will no longer appear in '
          'the marketplace.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.sold),
            child: const Text('Mark as sold'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final Listing? marked = await _controller.markSold(current.id);
    if (!mounted || marked == null) {
      return;
    }
    setState(() => _listing = marked);
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

  /// The gallery's height. Shorter than the buyer's, because the seller is
  /// here for the status and the actions rather than the photographs.
  static const double _galleryHeight = 200;

  @override
  Widget build(BuildContext context) {
    // No app bar: as in the approved design the photo runs to the top edge and
    // the back and edit buttons float over it.
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? child) {
          final Listing listing = _current();
          final SellerListingState state = _controller.state;
          final bool busy =
              state.isActioning && state.actionListingId == listing.id;
          final bool canEdit = SellerListingController.canEdit(listing);
          // An active listing carries Edit in the bottom bar, beside Mark as
          // sold; every other editable state keeps it over the photo.
          final bool editInBar =
              canEdit && SellerListingController.canMarkSold(listing);
          final double topInset = MediaQuery.paddingOf(context).top;

          return Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    Stack(
                      children: <Widget>[
                        ListingPhotoCarousel(
                          listing: listing,
                          height: _galleryHeight + topInset,
                        ),
                        Positioned(
                          left: AppSpacing.sm,
                          right: AppSpacing.sm,
                          top: topInset + AppSpacing.xs,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              _FloatingButton(
                                icon: Icons.arrow_back,
                                tooltip: 'Back',
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                              ),
                              if (canEdit && !editInBar)
                                _FloatingButton(
                                  icon: Icons.edit_outlined,
                                  tooltip: 'Edit listing',
                                  onPressed: _edit,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.screenGutter),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _Summary(
                            listing: listing,
                            message: state.actionMessage,
                            conflict: state.conflictMessage,
                            error: state.actionErrorMessage,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _FactsGrid(listing: listing),
                          ..._details(listing),
                          if (listing.createdAt != null) ...<Widget>[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'Created '
                              '${AppFormatters.formatDateTime(listing.createdAt!)}'
                              '${listing.updatedAt != null ? ' · updated ${AppFormatters.formatDateTime(listing.updatedAt!)}' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _ActionBar(
                listing: listing,
                busy: busy,
                onEdit: editInBar ? _edit : null,
                onSubmit: _submit,
                onMarkSold: _markSold,
                onDelete: _delete,
              ),
            ],
          );
        },
      ),
    );
  }

  /// The facts that do not fit the six-cell grid, as one "Details" section.
  /// Empty when the listing records none of them.
  List<Widget> _details(Listing listing) {
    bool filled(String? value) => value != null && value.trim().isNotEmpty;

    final List<Widget> rows = <Widget>[
      if (filled(listing.shortDescription))
        DetailRow(label: 'Description', value: listing.shortDescription),
      if (filled(listing.genderLabel))
        DetailRow(label: 'Gender', value: listing.genderLabel!),
      if (filled(listing.vaccination))
        DetailRow(label: 'Vaccination', value: listing.vaccination!),
      if (filled(listing.additionalNotes))
        DetailRow(label: 'Notes', value: listing.additionalNotes!),
    ];
    if (rows.isEmpty) {
      return const <Widget>[];
    }
    return <Widget>[
      const SizedBox(height: AppSpacing.md),
      SectionCard(title: 'Details', children: rows),
    ];
  }
}

/// A round white button that sits on top of the photo.
class _FloatingButton extends StatelessWidget {
  const _FloatingButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.94),
      shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: AppColors.text),
        onPressed: onPressed,
      ),
    );
  }
}

/// The name and status, what the status means, any message from the last
/// action, then the price and where the animal is.
class _Summary extends StatelessWidget {
  const _Summary({
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(listing.title, style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(width: AppSpacing.sm),
            ListingStatusChip(status: listing.status),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          listingStatusExplanation(listing.status),
          style: theme.textTheme.bodySmall,
        ),
        if (conflict != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          ListingConflictNotice(message: conflict!),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          ListingActionErrorBanner(message: error!),
        ],
        if (message != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(message!, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'Price and location',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              AppFormatters.formatMoney(listing.askingPrice) ??
                  listing.askingPrice,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: AppColors.primary,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                listing.location,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Six facts in a bordered three-column grid: Type, Breed, Quantity, Age,
/// Weight and Health. A missing fact shows a dash rather than hiding, so the
/// grid keeps its shape.
class _FactsGrid extends StatelessWidget {
  const _FactsGrid({required this.listing});

  final Listing listing;

  static String? _present(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  static String? _capitalised(String? value) {
    final String? text = _present(value);
    return text == null ? null : '${text[0].toUpperCase()}${text.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final List<(String, String?)> facts = <(String, String?)>[
      ('Type', _capitalised(listing.livestockType)),
      ('Breed', _present(listing.breed)),
      (
        'Quantity',
        '${listing.quantity} ${listing.quantity == 1 ? 'head' : 'heads'}',
      ),
      ('Age', listing.ageLabel),
      ('Weight', listing.weightLabel),
      ('Health', _present(listing.healthStatus)),
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

/// The actions available on this listing, pinned to the bottom of the screen.
///
/// Bottom rather than in the app bar, and pinned rather than at the end of the
/// scroll: a seller who has scrolled to the bottom of a long notes field should
/// not have to scroll back up to submit or delete. An active listing pairs
/// Edit with Mark as sold here, as the approved design does; other editable
/// states keep Edit over the photo.
///
/// A listing with no available action shows the reason instead of a row of
/// disabled buttons. There is a difference between "you may not" and "there is
/// nothing to do yet", and a greyed-out button does not tell the user which one
/// they are looking at.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.listing,
    required this.busy,
    required this.onEdit,
    required this.onSubmit,
    required this.onMarkSold,
    required this.onDelete,
  });

  final Listing listing;
  final bool busy;

  /// Null when Edit is not offered in the bar.
  final VoidCallback? onEdit;
  final VoidCallback onSubmit;
  final VoidCallback onMarkSold;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final bool canSubmit = SellerListingController.canSubmit(listing);
    final bool canMarkSold = SellerListingController.canMarkSold(listing);
    final bool canDelete = SellerListingController.canDelete(listing);
    final bool hasPhotos = SellerListingController.hasSubmissionPhotos(listing);

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (canSubmit && !hasPhotos) ...<Widget>[
                const ListingPhotoRequirementNotice(),
                const SizedBox(height: AppSpacing.sm),
              ],
              // The three flags are mutually constrained by the listing
              // lifecycle: `canSubmit` is draft-only, `canMarkSold` is
              // active-only, and `canDelete` covers draft/inactive. Checking
              // them in priority order avoids enumerating impossible boolean
              // combinations or hiding one behind a wildcard.
              if (canMarkSold)
                Row(
                  children: <Widget>[
                    if (onEdit != null) ...<Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit listing'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : onMarkSold,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Mark as sold'),
                      ),
                    ),
                  ],
                )
              else if (canSubmit)
                // A draft may be deleted or submitted for review; both buttons
                // share the busy flag so a second action while one is running
                // lands on a 409 waiting to happen.
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : onDelete,
                        child: const Text('Delete listing'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: busy || !hasPhotos ? null : onSubmit,
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
                )
              else if (canDelete)
                // `inactive`: only Delete.
                OutlinedButton(
                  onPressed: busy ? null : onDelete,
                  child: const Text('Delete listing'),
                )
              else
                // A `pending` listing is in an administrator's queue, a `sold`
                // one is a record. Either way the seller has nothing to do, and
                // the panel above already says so.
                const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }
}
