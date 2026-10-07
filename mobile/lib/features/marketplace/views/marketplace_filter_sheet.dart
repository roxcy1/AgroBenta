import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_spacing.dart';
import '../state/listing_filters.dart';

/// Opens the marketplace filter sheet and resolves to the applied filters, or
/// `null` if the buyer dismissed it.
///
/// Returning `null` rather than the unchanged filters on dismissal is what lets
/// the caller treat "cancelled" as "make no request at all" — re-querying the
/// server for a sheet the user closed would be exactly the redundant call
/// `mobile/AGENTS.md` warns about.
Future<ListingFilters?> showMarketplaceFilterSheet({
  required BuildContext context,
  required ListingFilters filters,
}) {
  return showModalBottomSheet<ListingFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) =>
        _MarketplaceFilterSheet(filters: filters),
  );
}

/// The filter form.
///
/// A sheet rather than a separate screen: filters are a short, dismissible
/// adjustment to something the buyer is already looking at, and pushing a route
/// for it would make the relationship to the list less obvious.
///
/// The controllers hold the text so a half-typed price is not destroyed by a
/// rebuild, and they are disposed with the sheet.
class _MarketplaceFilterSheet extends StatefulWidget {
  const _MarketplaceFilterSheet({required this.filters});

  final ListingFilters filters;

  @override
  State<_MarketplaceFilterSheet> createState() =>
      _MarketplaceFilterSheetState();
}

class _MarketplaceFilterSheetState extends State<_MarketplaceFilterSheet> {
  late final TextEditingController _livestockType = TextEditingController(
    text: widget.filters.livestockType,
  );
  late final TextEditingController _location = TextEditingController(
    text: widget.filters.location,
  );
  late final TextEditingController _minPrice = TextEditingController(
    text: widget.filters.minPrice,
  );
  late final TextEditingController _maxPrice = TextEditingController(
    text: widget.filters.maxPrice,
  );

  /// Set when the range is the wrong way round, to explain the problem inline
  /// rather than only refusing to apply.
  bool _showRangeError = false;

  @override
  void dispose() {
    _livestockType.dispose();
    _location.dispose();
    _minPrice.dispose();
    _maxPrice.dispose();
    super.dispose();
  }

  /// The filters represented by the current field contents.
  ///
  /// Read from the controllers rather than held in state, so there is a single
  /// source of truth: no possibility of the applied value and the displayed
  /// value disagreeing after an edit.
  ListingFilters get _current => ListingFilters(
    livestockType: _livestockType.text.trim(),
    location: _location.text.trim(),
    minPrice: _minPrice.text.trim(),
    maxPrice: _maxPrice.text.trim(),
  );

  void _apply() {
    final ListingFilters next = _current;

    if (next.hasInvertedPriceRange) {
      setState(() => _showRangeError = true);
      return;
    }

    Navigator.of(context).pop(next);
  }

  /// Clears every field and applies the empty selection immediately.
  ///
  /// Applies rather than merely resetting the fields: a "Clear all" that still
  /// required a second "Apply" tap leaves the list showing results that no
  /// longer match what the form says.
  void _clearAll() {
    Navigator.of(context).pop(ListingFilters.none);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      // Lifts the sheet above the keyboard, which matters as soon as the price
      // fields are focused — without it the Apply row sits under the keyboard
      // and the form is unusable.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            0,
            AppSpacing.screenGutter,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Filters', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Narrow the listings to what you are looking for. Leave a field '
                'empty for no limit.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _livestockType,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Livestock type',
                  hintText: 'e.g. Cattle',
                  prefixIcon: Icon(Icons.pets_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Matches the seller’s wording exactly, and capitalisation is '
                'significant.',
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _location,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  hintText: 'e.g. Nueva Ecija',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'An exact match on the seller’s location, so partial names are '
                'best left blank.',
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _minPrice,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[_decimalOnly],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Min price',
                        hintText: '0',
                        prefixText: '₱ ',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _maxPrice,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[_decimalOnly],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (String _) => _apply(),
                      decoration: const InputDecoration(
                        labelText: 'Max price',
                        hintText: 'No limit',
                        prefixText: '₱ ',
                      ),
                    ),
                  ),
                ],
              ),
              if (_showRangeError) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'The minimum price is higher than the maximum price.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _apply,
                child: const Text('Apply filters'),
              ),
              if (widget.filters.isActive) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  onPressed: _clearAll,
                  child: const Text('Clear all'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Allows digits and at most one decimal point.
///
/// A convenience, not validation: the server's `numeric,min:0` rule is the
/// authority, and this simply keeps the keyboard from being unable to type a
/// value the app will accept. Negative numbers are impossible to enter, which
/// matches `min:0`.
final TextInputFormatter _decimalOnly = FilteringTextInputFormatter.allow(
  RegExp(r'^\d*\.?\d*'),
);
