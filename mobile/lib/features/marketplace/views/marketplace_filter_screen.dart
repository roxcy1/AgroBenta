import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/livestock_type.dart';
import '../../../widgets/field_label.dart';
import '../../livestock_types/state/livestock_types_controller.dart';
import '../../livestock_types/state/livestock_types_scope.dart';
import '../../livestock_types/state/livestock_types_state.dart';
import '../state/listing_filters.dart';

/// Opens the Filters page and resolves to the applied filters, or `null` when
/// the buyer left without applying.
///
/// A full-screen child route, the navigation model `mobile/DESIGN.md` §8/§10
/// uses for Filters, Details and other child screens. It is pushed over the
/// Buyer shell, so the bottom navigation is hidden while it is open, and
/// popping it returns to whichever screen opened it — Marketplace or Home.
///
/// Returning `null` rather than the unchanged filters is what lets the caller
/// treat "backed out" as "make no request at all" — re-querying the server for
/// a filter form the user abandoned would be exactly the redundant call
/// `mobile/AGENTS.md` warns about.
Future<ListingFilters?> showMarketplaceFilterScreen({
  required BuildContext context,
  required ListingFilters filters,
}) {
  return Navigator.of(context).push<ListingFilters>(
    MaterialPageRoute<ListingFilters>(
      builder: (BuildContext context) =>
          MarketplaceFilterScreen(initial: filters),
    ),
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

/// The Filters page, over the existing marketplace filter state.
///
/// Presentation only — it edits a copy of the form locally and hands the
/// finished [ListingFilters] back to the caller, which applies them through
/// `MarketplaceController`. It makes no request of its own.
///
/// Reset clears the draft without leaving the page. Apply pops with the
/// selection. Back pops with `null`, discarding the draft.
class MarketplaceFilterScreen extends StatefulWidget {
  const MarketplaceFilterScreen({required this.initial, super.key});

  /// The filters currently applied, used to pre-fill the form.
  ///
  /// Reopening preserves what is applied, per the design; Reset clears the
  /// form without applying, and Back discards everything.
  final ListingFilters initial;

  @override
  State<MarketplaceFilterScreen> createState() =>
      _MarketplaceFilterScreenState();
}

class _MarketplaceFilterScreenState extends State<MarketplaceFilterScreen> {
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

  /// Guards against a second Apply while the first is already popping the
  /// page. Without it, a double tap could pop the route underneath too.
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
      catalog: _catalog.state.types,
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
  /// fields, change their mind and go Back. Clearing the applied filters is
  /// done by Reset followed by Apply.
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
    final Set<String> available = ListingFilters.catalogBreeds(
      _livestockTypes,
      _catalog.state.types,
    ).toSet();
    _breeds = _breeds
        .where((String breed) => available.contains(breed))
        .toList(growable: false);
  }

  /// The union of the selected types' catalog breeds, in catalog order.
  List<String> _availableBreeds() =>
      ListingFilters.catalogBreeds(_livestockTypes, _catalog.state.types);

  Future<void> _openBreedPicker() async {
    final List<String> available = _availableBreeds();
    final List<String> selected = List<String>.of(_breeds);

    final List<String>? result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
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
                      style: Theme.of(context).textTheme.titleMedium,
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
                            title: Text(breed),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Filters')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(child: _buildBody()),
            _buildActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return ListenableBuilder(
      listenable: _catalog,
      builder: (BuildContext context, Widget? child) {
        final LivestockTypesState catalogState = _catalog.state;

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            AppSpacing.md,
          ),
          children: <Widget>[
            _FilterSection(
              icon: Icons.pets,
              title: 'Animal Type',
              helper: 'Select one or more animal types.',
              child: _buildAnimalTypes(catalogState),
            ),
            const SizedBox(height: AppSpacing.md),
            _FilterSection(
              icon: Icons.style_outlined,
              title: 'Breed',
              helper: 'Choose breed(s) for the selected animal types.',
              child: _buildBreedSelector(),
            ),
            const SizedBox(height: AppSpacing.md),
            _FilterSection(
              icon: Icons.sell_outlined,
              title: 'Price Range',
              child: _buildPriceFields(),
            ),
            const SizedBox(height: AppSpacing.md),
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

  /// The pinned bottom action area: Reset clears the draft, Apply returns the
  /// selection. Back is the app bar's own button, so it is not repeated here.
  Widget _buildActionBar() {
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
              onPressed: _reset,
              child: const Text('Reset'),
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
    );
  }

  Widget _buildAnimalTypes(LivestockTypesState catalogState) {
    if (catalogState.hasFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            catalogState.errorMessage ?? 'Could not load livestock types.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton(onPressed: _catalog.retry, child: const Text('Retry')),
        ],
      );
    }
    if (!catalogState.isReady) {
      return const Center(child: CircularProgressIndicator());
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
              _AnimalTile(
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
        Semantics(
          button: true,
          enabled: enabled,
          label: 'Breed',
          child: InkWell(
            onTap: enabled ? _openBreedPicker : null,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              height: AppSizes.controlHeight,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: enabled ? AppColors.surface : AppColors.background,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: enabled ? AppColors.fieldBorder : AppColors.border,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _breeds.isEmpty
                            ? AppColors.textHint
                            : AppColors.text,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppColors.textHint,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!enabled) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Choose at least one animal type to see breeds.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _buildPriceFields() {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _FilterTextField(
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
              child: _FilterTextField(
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
          Text(
            'The minimum price is higher than the maximum price.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }

  Widget _buildAdditionalFilters() {
    final ThemeData theme = Theme.of(context);

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
              child: _FilterTextField(
                controller: _minAge,
                label: 'Min',
                onChanged: (String _) => setState(() => _showAgeError = false),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _FilterTextField(
                controller: _maxAge,
                label: 'Max',
                onChanged: (String _) => setState(() => _showAgeError = false),
              ),
            ),
          ],
        ),
        if (_showAgeError) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The minimum age is higher than the maximum age.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        const _SubLabel('Weight (kg)', icon: Icons.monitor_weight_outlined),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _FilterTextField(
                controller: _minWeight,
                label: 'Min',
                onChanged: (String _) =>
                    setState(() => _showWeightError = false),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _FilterTextField(
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
          Text(
            'The minimum weight is higher than the maximum weight.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

/// A titled section card holding one group of controls.
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
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xxs),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            if (helper != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(helper!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
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
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(text, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// One Animal Type tile: a selectable button in the same light chip language
/// as the Browse category chips.
///
/// The whole tile is the tap target, well past the 48dp minimum.
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
    return Semantics(
      button: true,
      selected: selected,
      label: animal.label,
      child: Material(
        color: selected ? AppColors.primary : AppColors.surface,
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
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              animal.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.text,
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
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          backgroundColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) => states.contains(WidgetState.selected)
                ? AppColors.surface
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) => states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
          side: const WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: Colors.transparent),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          textStyle: WidgetStatePropertyAll<TextStyle?>(
            theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        segments: const <ButtonSegment<String>>[
          ButtonSegment<String>(value: '', label: Text('Any')),
          ButtonSegment<String>(value: 'male', label: Text('Male')),
          ButtonSegment<String>(value: 'female', label: Text('Female')),
        ],
        selected: <String>{value},
        onSelectionChanged: (Set<String> selection) =>
            onChanged(selection.first),
      ),
    );
  }
}

/// A numeric range field on the light page, using the app's standard labelled
/// field treatment.
class _FilterTextField extends StatelessWidget {
  const _FilterTextField({
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
      onChanged: onChanged,
      decoration: InputDecoration(
        label: FieldLabel(label),
        hintText: hint,
        prefixText: prefixText,
      ),
    );
  }
}
