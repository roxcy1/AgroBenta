import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/livestock_type.dart';
import '../../livestock_types/state/livestock_types_controller.dart';
import '../../livestock_types/state/livestock_types_scope.dart';
import '../../livestock_types/state/livestock_types_state.dart';
import '../state/listing_filters.dart';

/// Opens the Filter Livestock dialog and resolves to the applied filters, or
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
  return showDialog<ListingFilters>(
    context: context,
    barrierColor: Colors.black,
    builder: (BuildContext context) =>
        MarketplaceFilterDialog(initial: filters),
  );
}

/// One Animal Type shortcut.
class _AnimalType {
  const _AnimalType({required this.label, required this.value});

  final String label;
  final String value;

  factory _AnimalType.fromCatalog(LivestockType type) =>
      _AnimalType(label: type.label, value: type.value);
}

/// The Filter Livestock dialog, over the existing marketplace filter state.
///
/// Presentation only — it edits a copy of the form locally and hands the
/// finished [ListingFilters] back to the caller, which applies them through
/// `MarketplaceController`. It makes no request of its own.
///
/// The dialog is the one dark surface in the app, matching the approved
/// reference. Its colours live in [AppColors] beside the light palette rather
/// than in a second `ThemeData`; see the note there.
class MarketplaceFilterDialog extends StatefulWidget {
  const MarketplaceFilterDialog({required this.initial, super.key});

  /// The filters currently applied, used to pre-fill the form.
  ///
  /// Reopening preserves what is applied, per the design; Reset clears the
  /// form without applying, and Cancel discards everything.
  final ListingFilters initial;

  @override
  State<MarketplaceFilterDialog> createState() =>
      _MarketplaceFilterDialogState();
}

class _MarketplaceFilterDialogState extends State<MarketplaceFilterDialog> {
  late final LivestockTypesController _catalog;
  late List<String> _livestockTypes;
  late List<String> _breeds;
  late String _gender;
  late final TextEditingController _minPrice = TextEditingController();
  late final TextEditingController _maxPrice = TextEditingController();
  late final TextEditingController _minAge = TextEditingController();
  late final TextEditingController _maxAge = TextEditingController();
  late final TextEditingController _minWeight = TextEditingController();
  late final TextEditingController _maxWeight = TextEditingController();

  /// Set when a range is the wrong way round, to explain the problem inline
  /// rather than only refusing to apply.
  bool _showPriceError = false;
  bool _showAgeError = false;
  bool _showWeightError = false;

  /// Guards against a second Apply while the first is still resolving.
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _catalog = LivestockTypesScope.readOf(context);
    _livestockTypes = List<String>.of(widget.initial.livestockTypes);
    _breeds = List<String>.of(widget.initial.breeds);
    _gender = widget.initial.gender;
    _minPrice.text = widget.initial.minPrice;
    _maxPrice.text = widget.initial.maxPrice;
    _minAge.text = widget.initial.minAge;
    _maxAge.text = widget.initial.maxAge;
    _minWeight.text = widget.initial.minWeight;
    _maxWeight.text = widget.initial.maxWeight;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _catalog.ensureLoaded();
    });
  }

  @override
  void dispose() {
    _minPrice.dispose();
    _maxPrice.dispose();
    _minAge.dispose();
    _maxAge.dispose();
    _minWeight.dispose();
    _maxWeight.dispose();
    super.dispose();
  }

  /// The filters represented by the current field contents.
  ListingFilters get _current => ListingFilters(
    livestockTypes: _livestockTypes,
    breeds: _breeds,
    gender: _gender,
    minAge: _minAge.text.trim(),
    maxAge: _maxAge.text.trim(),
    minWeight: _minWeight.text.trim(),
    maxWeight: _maxWeight.text.trim(),
    minPrice: _minPrice.text.trim(),
    maxPrice: _maxPrice.text.trim(),
  );

  void _apply() {
    if (_submitting) {
      return;
    }

    final ListingFilters next = _current.pruneIncompatibleBreeds(
      _livestockTypes,
    );
    if (next.hasInvertedPriceRange ||
        next.hasInvertedAgeRange ||
        next.hasInvertedWeightRange) {
      setState(() {
        _showPriceError = next.hasInvertedPriceRange;
        _showAgeError = next.hasInvertedAgeRange;
        _showWeightError = next.hasInvertedWeightRange;
      });
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
      _livestockTypes = <String>[];
      _breeds = <String>[];
      _gender = '';
      _minPrice.clear();
      _maxPrice.clear();
      _minAge.clear();
      _maxAge.clear();
      _minWeight.clear();
      _maxWeight.clear();
      _showPriceError = false;
      _showAgeError = false;
      _showWeightError = false;
    });
  }

  /// Discards the form and returns to the caller.
  void _cancel() => Navigator.of(context).pop();

  bool _isAnimalSelected(String value) => _livestockTypes.contains(value);

  void _toggleAnimal(_AnimalType animal) {
    setState(() {
      if (_isAnimalSelected(animal.value)) {
        _livestockTypes = <String>[..._livestockTypes]..remove(animal.value);
      } else {
        _livestockTypes = <String>[..._livestockTypes, animal.value];
      }
      _pruneBreeds();
    });
  }

  /// Drops breeds whose animal type was just deselected.
  ///
  /// A breed is only meaningful with its species, and leaving a stale breed in
  /// the selection would send a filter that can never match a visible listing.
  void _pruneBreeds() {
    final Set<String> available = _availableBreeds().toSet();
    _breeds = _breeds
        .where((String breed) => available.contains(breed))
        .toList(growable: false);
  }

  /// The union of the selected types' catalog breeds, in catalog order.
  List<String> _availableBreeds() {
    final List<String> breeds = <String>[];
    final List<LivestockType> catalog = _catalog.state.types;

    for (final String type in _livestockTypes) {
      for (final LivestockType entry in catalog) {
        if (entry.value != type) {
          continue;
        }
        for (final String breed in entry.breeds) {
          if (!breeds.contains(breed)) {
            breeds.add(breed);
          }
        }
      }
    }

    return breeds;
  }

  Future<void> _openBreedPicker() async {
    final List<String> available = _availableBreeds();
    final List<String> selected = List<String>.of(_breeds);

    final List<String>? result = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: AppColors.filterDarkSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (BuildContext context) => StatefulBuilder(
        builder:
            (
              BuildContext context,
              void Function(void Function()) setSheetState,
            ) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.xs,
                    ),
                    child: Text(
                      'Select breeds',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.filterDarkText,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        for (final String breed in available)
                          CheckboxListTile(
                            value: selected.contains(breed),
                            onChanged: (bool? value) {
                              setSheetState(() {
                                if (value == true) {
                                  selected.add(breed);
                                } else {
                                  selected.remove(breed);
                                }
                              });
                            },
                            title: Text(
                              breed,
                              style: const TextStyle(
                                color: AppColors.filterDarkText,
                              ),
                            ),
                            activeColor: AppColors.filterDarkAccent,
                            checkColor: Colors.black,
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(selected),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.filterDarkAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Done'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ),
    );

    if (result != null) {
      setState(() => _breeds = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.filterDarkSurface,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(),
            Flexible(child: _buildBody()),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned(
            left: 0,
            child: IconButton(
              onPressed: _cancel,
              icon: const Icon(Icons.close, size: 20),
              color: AppColors.filterDarkText,
              tooltip: 'Close',
            ),
          ),
          Text(
            'Filter Livestock',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.filterDarkText,
              fontWeight: FontWeight.w700,
            ),
          ),
          Positioned(
            right: 0,
            child: TextButton(
              onPressed: _reset,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.filterDarkAccent,
              ),
              child: const Text('Reset'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return ListenableBuilder(
      listenable: _catalog,
      builder: (BuildContext context, Widget? child) {
        final LivestockTypesState catalogState = _catalog.state;

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: <Widget>[
            _FilterSection(
              icon: Icons.pets,
              title: 'Animal Type',
              helper: 'Select one or more animal types.',
              child: _buildAnimalTypes(catalogState),
            ),
            const SizedBox(height: AppSpacing.sm),
            _FilterSection(
              icon: Icons.style_outlined,
              title: 'Breed',
              helper: 'Choose breed(s) for the selected animal types.',
              child: _buildBreedSelector(),
            ),
            const SizedBox(height: AppSpacing.sm),
            _FilterSection(
              icon: Icons.sell_outlined,
              title: 'Price Range',
              child: _buildPriceFields(),
            ),
            const SizedBox(height: AppSpacing.sm),
            _FilterSection(
              icon: Icons.tune,
              title: 'Additional Filters',
              child: _buildAdditionalFilters(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: _cancel,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppSizes.controlHeight),
                  foregroundColor: AppColors.filterDarkText,
                  side: const BorderSide(color: AppColors.filterDarkBorder),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: _apply,
                icon: const Icon(Icons.filter_alt_outlined, size: 18),
                label: const Text('Apply Filters'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppSizes.controlHeight),
                  backgroundColor: AppColors.filterDarkAccent,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimalTypes(LivestockTypesState catalogState) {
    if (catalogState.hasFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            catalogState.errorMessage ?? 'Could not load livestock types.',
            style: const TextStyle(color: AppColors.filterDarkTextSecondary),
          ),
          TextButton(
            onPressed: _catalog.retry,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.filterDarkAccent,
            ),
            child: const Text('Retry'),
          ),
        ],
      );
    }
    if (!catalogState.isReady) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.filterDarkAccent),
      );
    }

    final List<_AnimalType> animals = catalogState.types
        .map(_AnimalType.fromCatalog)
        .toList(growable: false);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = AppSpacing.sm;
        final int columns = (constraints.maxWidth / 108).floor().clamp(2, 4);
        final double tileWidth =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final _AnimalType animal in animals)
              _DarkAnimalTile(
                key: ValueKey<String>('animal-type-${animal.value}'),
                animal: animal,
                width: tileWidth,
                selected: _isAnimalSelected(animal.value),
                onTap: () => _toggleAnimal(animal),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBreedSelector() {
    final bool enabled = _livestockTypes.isNotEmpty;
    final String text = _breeds.isEmpty
        ? (enabled ? 'Select breed(s)' : 'Select an animal type first')
        : _breeds.join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          onTap: enabled ? _openBreedPicker : null,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            height: AppSizes.controlHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.filterDarkField,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.filterDarkFieldBorder),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _breeds.isEmpty
                          ? AppColors.filterDarkTextSecondary
                          : AppColors.filterDarkText,
                    ),
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down,
                  size: 20,
                  color: AppColors.filterDarkTextSecondary,
                ),
              ],
            ),
          ),
        ),
        if (!enabled) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Choose at least one animal type to see breeds.',
            style: TextStyle(
              color: AppColors.filterDarkTextSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPriceFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _DarkTextField(
                controller: _minPrice,
                label: 'Minimum price',
                hint: '0',
                prefixText: '₱ ',
                onChanged: (String _) =>
                    setState(() => _showPriceError = false),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _DarkTextField(
                controller: _maxPrice,
                label: 'Maximum price',
                hint: 'No limit',
                prefixText: '₱ ',
                onChanged: (String _) =>
                    setState(() => _showPriceError = false),
              ),
            ),
          ],
        ),
        if (_showPriceError) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'The minimum price is higher than the maximum price.',
            style: TextStyle(color: AppColors.filterDarkAccent, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildAdditionalFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SubLabel('Sex'),
        _SegmentedControl(
          value: _gender,
          onChanged: (String value) => setState(() => _gender = value),
        ),
        const SizedBox(height: AppSpacing.md),
        const _SubLabel('Age (months)', icon: Icons.cake_outlined),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _DarkTextField(
                controller: _minAge,
                label: 'Min',
                onChanged: (String _) => setState(() => _showAgeError = false),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _DarkTextField(
                controller: _maxAge,
                label: 'Max',
                onChanged: (String _) => setState(() => _showAgeError = false),
              ),
            ),
          ],
        ),
        if (_showAgeError) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'The minimum age is higher than the maximum age.',
            style: TextStyle(color: AppColors.filterDarkAccent, fontSize: 12),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        const _SubLabel('Weight (kg)', icon: Icons.monitor_weight_outlined),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _DarkTextField(
                controller: _minWeight,
                label: 'Min',
                onChanged: (String _) =>
                    setState(() => _showWeightError = false),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _DarkTextField(
                controller: _maxWeight,
                label: 'Max',
                onChanged: (String _) =>
                    setState(() => _showWeightError = false),
              ),
            ),
          ],
        ),
        if (_showWeightError) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'The minimum weight is higher than the maximum weight.',
            style: TextStyle(color: AppColors.filterDarkAccent, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// A titled dark panel holding one group of controls.
class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.icon,
    required this.title,
    required this.child,
    this.helper,
  });

  final IconData icon;
  final String title;
  final String? helper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.filterDarkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.filterDarkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: AppColors.filterDarkAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 18, color: AppColors.filterDarkAccent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.filterDarkText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (helper != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              helper!,
              style: const TextStyle(
                color: AppColors.filterDarkTextSecondary,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// A bold label for a sub-filter inside the Additional Filters section.
class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text, {this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 16, color: AppColors.filterDarkAccent),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            text,
            style: const TextStyle(
              color: AppColors.filterDarkText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// One Animal Type tile: plain text on a dark rounded button.
///
/// The whole tile is the tap target, well past the 48dp minimum.
class _DarkAnimalTile extends StatelessWidget {
  const _DarkAnimalTile({
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
    return Semantics(
      button: true,
      selected: selected,
      label: animal.label,
      child: Material(
        color: selected
            ? AppColors.filterDarkAccent.withValues(alpha: 0.18)
            : AppColors.filterDarkTile,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: width,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected
                    ? AppColors.filterDarkAccent
                    : AppColors.filterDarkBorder,
                width: selected ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              animal.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected
                    ? AppColors.filterDarkAccent
                    : AppColors.filterDarkText,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// The Any / Male / Female choice, rendered as one segmented control.
class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.filterDarkCard,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.filterDarkBorder),
      ),
      child: Row(
        children: <Widget>[
          _segment('Any', ''),
          _segment('Male', 'male'),
          _segment('Female', 'female'),
        ],
      ),
    );
  }

  Widget _segment(String label, String segmentValue) {
    final bool selected = value == segmentValue;

    return Expanded(
      child: InkWell(
        onTap: () => onChanged(segmentValue),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.filterDarkTile : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? AppColors.filterDarkText
                  : AppColors.filterDarkTextSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// A text field on the dark dialog surface.
class _DarkTextField extends StatelessWidget {
  const _DarkTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.prefixText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? prefixText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      style: const TextStyle(color: AppColors.filterDarkText),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
        labelStyle: const TextStyle(
          color: AppColors.filterDarkTextSecondary,
          fontSize: 12,
        ),
        hintStyle: const TextStyle(
          color: AppColors.filterDarkTextSecondary,
          fontSize: 14,
        ),
        prefixStyle: const TextStyle(color: AppColors.filterDarkText),
        filled: true,
        fillColor: AppColors.filterDarkField,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.filterDarkFieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.filterDarkAccent),
        ),
      ),
    );
  }
}
