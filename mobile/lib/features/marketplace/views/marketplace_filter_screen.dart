import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../state/listing_filters.dart';

/// Opens the Filter Livestock screen and resolves to the applied filters, or
/// `null` when the buyer cancelled or backed out.
///
/// Returning `null` rather than the unchanged filters is what lets the caller
/// treat "cancelled" as "make no request at all" — re-querying the server for a
/// filter form the user abandoned would be exactly the redundant call
/// `mobile/AGENTS.md` warns about.
Future<ListingFilters?> showMarketplaceFilterScreen({
  required BuildContext context,
  required ListingFilters filters,
}) {
  return Navigator.of(context).push<ListingFilters>(
    MaterialPageRoute<ListingFilters>(
      fullscreenDialog: true,
      builder: (BuildContext context) =>
          MarketplaceFilterScreen(initial: filters),
    ),
  );
}

/// One Animal Type shortcut.
///
/// **[value] is a plain string, not an enum.** `listings.livestock_type` is free
/// text that the server matches exactly (functional documentation §4.1), and a
/// controlled vocabulary is still an open question (**OQ-04**). These four tiles
/// are therefore *shortcuts into the existing exact-match filter*, matching the
/// filter reference's order and labels — they are not a backend enum, and a
/// seller whose wording differs will not match. The "exact wording" field below
/// the tiles keeps any seller's wording reachable, which is why it is kept.
class _AnimalType {
  const _AnimalType({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;

  /// A brand-font livestock glyph.
  ///
  /// [FaIconData] rather than [IconData]: `font_awesome_flutter` 11 makes
  /// `IconData` final, so the two are not interchangeable. Icons are the closest
  /// Font Awesome **Free** provides — it has no goat or buffalo glyph, so `paw`
  /// and `hippo` stand in. That is a reported visual compromise, not an approved
  /// icon mapping.
  final FaIconData icon;

  static const List<_AnimalType> options = <_AnimalType>[
    _AnimalType(
      label: 'Cattle',
      value: 'Cattle',
      icon: FontAwesomeIcons.cow,
    ),
    _AnimalType(
      label: 'Swine',
      value: 'Swine',
      icon: FontAwesomeIcons.bacon,
    ),
    _AnimalType(label: 'Goat', value: 'Goat', icon: FontAwesomeIcons.paw),
    _AnimalType(
      label: 'Carabao',
      value: 'Carabao',
      icon: FontAwesomeIcons.hippo,
    ),
  ];
}

/// The Filter Livestock screen, over the existing marketplace filter state.
///
/// A full route rather than the bottom sheet it replaces: the reference is a
/// header-and-sections page, and a sheet cannot carry a dark header with its own
/// title, reset and back affordances. The screen is **presentation only** — it
/// edits a copy of the form locally and hands the finished [ListingFilters] back
/// to the caller, which applies them through [MarketplaceController]. It makes
/// no request of its own.
///
/// ## Only supported filters are live
///
/// `GET /api/listings` accepts `search`, `livestock_type`, `location`,
/// `min_price`, `max_price`, `page` and `per_page` (`IndexListingRequest`). There
/// is **no** `condition`, `health_status` or `sort` parameter, and the endpoint
/// is always ordered `created_at DESC, id DESC`. So Condition, Health Status and
/// Sort By are rendered as visibly unavailable rather than as controls that
/// pretend to filter — the design's own rule ("report the gap instead of
/// inventing parameters"). See the section doc comments for the specifics.
class MarketplaceFilterScreen extends StatefulWidget {
  const MarketplaceFilterScreen({required this.initial, super.key});

  /// The filters currently applied, used to pre-fill the form.
  ///
  /// Reopening preserves what is applied, per the design; Reset clears the form
  /// without applying, and Cancel discards everything.
  final ListingFilters initial;

  @override
  State<MarketplaceFilterScreen> createState() =>
      _MarketplaceFilterScreenState();
}

class _MarketplaceFilterScreenState extends State<MarketplaceFilterScreen> {
  late final TextEditingController _livestockType = TextEditingController(
    text: widget.initial.livestockType,
  );
  late final TextEditingController _location = TextEditingController(
    text: widget.initial.location,
  );
  late final TextEditingController _minPrice = TextEditingController(
    text: widget.initial.minPrice,
  );
  late final TextEditingController _maxPrice = TextEditingController(
    text: widget.initial.maxPrice,
  );

  /// Set when the range is the wrong way round, to explain the problem inline
  /// rather than only refusing to apply.
  bool _showRangeError = false;

  /// Guards against a second Apply while the first is still resolving.
  bool _submitting = false;

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
  /// Read from the controllers rather than held in state, so the applied value
  /// and the displayed value cannot disagree after an edit.
  ListingFilters get _current => ListingFilters(
    livestockType: _livestockType.text.trim(),
    location: _location.text.trim(),
    minPrice: _minPrice.text.trim(),
    maxPrice: _maxPrice.text.trim(),
  );

  /// Validates, then returns the filters to the caller.
  ///
  /// Validation without clearing input: an impossible range is explained and the
  /// form is left exactly as the user typed it, so they can correct one field
  /// rather than start over.
  void _apply() {
    if (_submitting) {
      return;
    }

    final ListingFilters next = _current;
    if (next.hasInvertedPriceRange) {
      setState(() => _showRangeError = true);
      return;
    }

    _submitting = true;
    Navigator.of(context).pop(next);
  }

  /// Clears the form to its empty defaults **without** submitting it.
  ///
  /// The design's Reset is a form action, not an apply: the buyer may clear the
  /// fields, change their mind and Cancel. Clearing the applied filters is done
  /// by Reset followed by Apply.
  void _reset() {
    setState(() {
      _livestockType.clear();
      _location.clear();
      _minPrice.clear();
      _maxPrice.clear();
      _showRangeError = false;
    });
  }

  /// Discards the form and returns to the caller.
  void _cancel() => Navigator.of(context).pop();

  /// Whether the Animal Type tile for [value] is the current selection.
  ///
  /// The text field is the single source of truth, so a tile is selected only
  /// while the field holds exactly its value — which keeps tiles and free text
  /// from disagreeing.
  bool _isAnimalSelected(String value) => _livestockType.text.trim() == value;

  void _selectAnimal(_AnimalType animal) {
    setState(() {
      if (_isAnimalSelected(animal.value)) {
        // Tapping the selected tile clears it: the backend is a single
        // exact-match value, so "none" is expressed by an empty field.
        _livestockType.clear();
      } else {
        _livestockType.text = animal.value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Filter Livestock'),
        actions: <Widget>[
          TextButton(
            onPressed: _reset,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Reset'),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            AppSpacing.lg,
          ),
          children: <Widget>[
            _FilterSection(
              title: 'Animal Type',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      const double spacing = AppSpacing.sm;
                      final int columns = (constraints.maxWidth / 108)
                          .floor()
                          .clamp(2, 4);
                      final double tileWidth =
                          (constraints.maxWidth - (columns - 1) * spacing) /
                          columns;

                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: <Widget>[
                          for (final _AnimalType animal in _AnimalType.options)
                            _AnimalTile(
                              key: ValueKey<String>(
                                'animal-type-${animal.value}',
                              ),
                              animal: animal,
                              width: tileWidth,
                              selected: _isAnimalSelected(animal.value),
                              onTap: () => _selectAnimal(animal),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _livestockType,
                    textInputAction: TextInputAction.next,
                    onChanged: (String _) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Other — exact wording',
                      hintText: 'e.g. Holstein-Friesian',
                      prefixIcon: Icon(Icons.pets_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Animal Type matches the seller’s wording exactly. If a '
                    'listing does not appear, try the wording the seller used.',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _FilterSection(
              title: 'Price Range',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _minPrice,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: <TextInputFormatter>[
                            _priceInputFormatter,
                          ],
                          textInputAction: TextInputAction.next,
                          onChanged: (String _) {
                            if (_showRangeError) {
                              setState(() => _showRangeError = false);
                            }
                          },
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
                          inputFormatters: <TextInputFormatter>[
                            _priceInputFormatter,
                          ],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (String _) => _apply(),
                          onChanged: (String _) {
                            if (_showRangeError) {
                              setState(() => _showRangeError = false);
                            }
                          },
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
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _FilterSection(
              title: 'Location',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _location,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      hintText: 'e.g. Nueva Ecija',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'An exact match on the seller’s location. There is no list '
                    'of locations to pick from, and Location permission is not '
                    'requested.',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const _UnavailableSection(
              title: 'Condition',
              options: <String>['All', 'Young', 'Adult', 'Pregnant'],
              note:
                  'Not available yet. The marketplace API cannot filter by '
                  'condition, and this app will not invent one.',
            ),
            const SizedBox(height: AppSpacing.md),
            const _UnavailableSection(
              title: 'Health Status',
              options: <String>['All', 'Healthy', 'Needs Care'],
              note:
                  'Not available yet. The marketplace API cannot filter by '
                  'health status, and health is never inferred from a photo.',
            ),
            const SizedBox(height: AppSpacing.md),
            const _SortSection(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
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
                  onPressed: _cancel,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: _apply,
                  child: const Text('Apply Filters'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled white panel holding one group of controls.
class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// One Animal Type tile: a livestock glyph above its label.
///
/// The whole tile is the tap target, well past the 48dp minimum. The selected
/// treatment (green border, pale-green surface, green icon and text) and the
/// unselected treatment (light-gray surface, dark text) follow the reference.
class _AnimalTile extends StatelessWidget {
  const _AnimalTile({
    required this.animal,
    required this.width,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final _AnimalType animal;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color foreground =
        selected ? AppColors.primary : AppColors.text;

    return Semantics(
      button: true,
      selected: selected,
      label: animal.label,
      child: Material(
        color: selected ? AppColors.primarySurface : AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: width,
            height: 84,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                FaIcon(animal.icon, size: 22, color: foreground),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  animal.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A section whose options the API cannot back, rendered as clearly disabled.
///
/// The design lists these options; the server has no query parameter for either
/// (`IndexListingRequest`), so the control is not made interactive. Showing them
/// disabled with an explanation is honest — a buyer sees the option exists in
/// the product and learns it is not available yet, rather than either a control
/// that silently does nothing or a fabricated filter.
class _UnavailableSection extends StatelessWidget {
  const _UnavailableSection({
    required this.title,
    required this.options,
    required this.note,
  });

  final String title;
  final List<String> options;
  final String note;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return _FilterSection(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final String option in options)
                _DisabledPill(label: option),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.lock_outline,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(note, style: theme.textTheme.labelSmall),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A non-interactive chip, visually distinct from a live control.
class _DisabledPill extends StatelessWidget {
  const _DisabledPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// The Sort By section, showing the only order the endpoint provides.
///
/// `MarketplaceListingRepository` always orders `created_at DESC, id DESC` and
/// the request accepts no `sort` parameter, so "Newest First" is the whole
/// vocabulary. It is displayed as a fixed value rather than a one-item dropdown,
/// which would invite a tap that cannot change anything.
class _SortSection extends StatelessWidget {
  const _SortSection();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return _FilterSection(
      title: 'Sort By',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.sort,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Newest First',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Newest first is the only order the marketplace provides.',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// Allows digits and at most one decimal point.
///
/// A convenience, not validation: the server's `numeric,min:0` rule is the
/// authority. It cannot express a negative number, which matches `min:0`, and it
/// keeps the keyboard from being unable to type a value the app will accept.
final TextInputFormatter _priceInputFormatter = FilteringTextInputFormatter.allow(
  RegExp(r'^\d*\.?\d*'),
);
