import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../features/trinidad_location/state/trinidad_location_controller.dart';
import '../features/trinidad_location/state/trinidad_location_scope.dart';
import '../features/trinidad_location/state/trinidad_location_state.dart';
import '../models/trinidad_location.dart';

const ValueKey<String> trinidadBarangayFieldKey = ValueKey<String>(
  'trinidad-barangay-field',
);
const ValueKey<String> trinidadBarangayFormFieldKey = ValueKey<String>(
  'trinidad-barangay-form-field',
);
const ValueKey<String> trinidadBarangaySearchFieldKey = ValueKey<String>(
  'trinidad-barangay-search-field',
);
const ValueKey<String> trinidadBarangayResultsKey = ValueKey<String>(
  'trinidad-barangay-results',
);
const ValueKey<String> trinidadBarangayDragHandleKey = ValueKey<String>(
  'trinidad-barangay-drag-handle',
);

/// Shared selector for addresses in Trinidad, Bohol.
///
/// It renders fixed region/municipality values and the backend-owned barangay
/// catalog. The parent owns the [TrinidadLocation] and persistence; this widget
/// only validates and reports edits.
class TrinidadLocationSelector extends StatefulWidget {
  const TrinidadLocationSelector({
    required this.value,
    required this.onChanged,
    required this.maxFormattedLength,
    this.isRequired = true,
    this.enabled = true,
    this.readOnly = false,
    this.legacyAddress,
    this.externalError,
    super.key,
  });

  final TrinidadLocation? value;
  final ValueChanged<TrinidadLocation?> onChanged;
  final int maxFormattedLength;
  final bool isRequired;
  final bool enabled;
  final bool readOnly;
  final String? legacyAddress;
  final String? externalError;

  @override
  State<TrinidadLocationSelector> createState() =>
      _TrinidadLocationSelectorState();
}

class _TrinidadLocationSelectorState extends State<TrinidadLocationSelector> {
  late final TrinidadLocationController _catalog;
  late final TextEditingController _streetPurok;

  @override
  void initState() {
    super.initState();
    _catalog = TrinidadLocationScope.readOf(context);
    _streetPurok = TextEditingController(text: widget.value?.streetPurok ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _catalog.ensureLoaded();
    });
  }

  @override
  void didUpdateWidget(TrinidadLocationSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String street = widget.value?.streetPurok ?? '';
    if (street != _streetPurok.text) {
      _streetPurok.value = TextEditingValue(
        text: street,
        selection: TextSelection.collapsed(offset: street.length),
      );
    }
  }

  @override
  void dispose() {
    _streetPurok.dispose();
    super.dispose();
  }

  void _emitStreet(String value) {
    final String? barangay = widget.value?.barangay;
    if (barangay == null && value.trim().isEmpty) {
      widget.onChanged(null);
      return;
    }
    widget.onChanged(TrinidadLocation(barangay: barangay, streetPurok: value));
  }

  void _selectBarangay(String? value) {
    final String? barangay = value == null || value.isEmpty ? null : value;
    final String street = _streetPurok.text;
    if (barangay == null && street.trim().isEmpty) {
      widget.onChanged(null);
      return;
    }
    widget.onChanged(TrinidadLocation(barangay: barangay, streetPurok: street));
  }

  Future<void> _openBarangayPicker(
    TrinidadLocationCatalog catalog,
    FormFieldState<String> field,
  ) async {
    if (!widget.enabled || widget.readOnly) return;

    final String? selected = field.value == null || field.value!.isEmpty
        ? null
        : field.value;
    final String? result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) => _BarangayPickerSheet(
        barangays: catalog.barangays,
        selectedBarangay: selected,
        allowClear: !widget.isRequired,
      ),
    );

    if (!mounted || result == null || !widget.enabled || widget.readOnly) {
      return;
    }

    field.didChange(result);
    _selectBarangay(result.isEmpty ? null : result);
  }

  String? _validateBarangay(String? value, TrinidadLocationCatalog catalog) {
    final String? serverError = widget.externalError;
    if (serverError != null) return serverError;

    final bool hasBarangay = catalog.containsBarangay(value);
    final bool hasStreet = _streetPurok.text.trim().isNotEmpty;
    if (!hasBarangay && (widget.isRequired || hasStreet)) {
      return 'Select a barangay.';
    }

    if (hasBarangay) {
      final TrinidadLocation location = TrinidadLocation(
        barangay: value,
        streetPurok: _streetPurok.text,
      );
      final String? formatted = location.formattedAddress(
        municipality: catalog.municipality,
        province: catalog.province,
      );
      if (formatted != null && formatted.length > widget.maxFormattedLength) {
        return 'The full address must be ${widget.maxFormattedLength} characters or fewer.';
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _catalog,
      builder: (BuildContext context, Widget? child) {
        final TrinidadLocationState state = _catalog.state;
        final TrinidadLocationCatalog? catalog = state.catalog;

        if (state.isLoading || catalog == null) {
          if (state.hasFailed) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  state.errorMessage ?? 'Could not load Trinidad barangays.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                TextButton(
                  onPressed: state.isLoading ? null : _catalog.retry,
                  child: const Text('Retry'),
                ),
              ],
            );
          }

          return const InputDecorator(
            decoration: InputDecoration(
              labelText: 'Barangay',
              border: OutlineInputBorder(),
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: Text('Loading Trinidad barangays...')),
              ],
            ),
          );
        }

        if (widget.readOnly) {
          return _readOnlyLocation(context, catalog);
        }

        final String? selectedBarangay =
            catalog.containsBarangay(widget.value?.barangay)
            ? widget.value!.barangay
            : null;
        final String? dropdownValue =
            selectedBarangay ??
            (!widget.isRequired && widget.value == null ? '' : null);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.legacyAddress != null &&
                widget.legacyAddress!.trim().isNotEmpty &&
                selectedBarangay == null) ...<Widget>[
              Text(
                'Saved address could not be matched to a barangay. It has not '
                'been changed; choose a barangay to replace it.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.legacyAddress!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            _fixedField(label: 'Province', value: catalog.provinceLabel),
            const SizedBox(height: AppSpacing.md),
            _fixedField(label: 'Municipality', value: catalog.municipality),
            const SizedBox(height: AppSpacing.md),
            FormField<String>(
              key: trinidadBarangayFormFieldKey,
              initialValue: dropdownValue,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (String? value) => _validateBarangay(value, catalog),
              builder: (FormFieldState<String> field) {
                final String? value = catalog.containsBarangay(field.value)
                    ? field.value
                    : null;
                final ThemeData theme = Theme.of(context);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      widget.isRequired ? 'Barangay *' : 'Barangay',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Material(
                      color: widget.enabled
                          ? AppColors.surface
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: InkWell(
                        key: trinidadBarangayFieldKey,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        onTap: widget.enabled
                            ? () => _openBarangayPicker(catalog, field)
                            : null,
                        child: Container(
                          constraints: const BoxConstraints(
                            minHeight: AppSizes.controlHeight,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  value ?? 'Select barangay',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: value == null
                                        ? theme.colorScheme.onSurfaceVariant
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Icon(
                                Icons.keyboard_arrow_down,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (field.errorText != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        field.errorText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _streetPurok,
              enabled: widget.enabled,
              readOnly: widget.readOnly,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: widget.maxFormattedLength,
              decoration: const InputDecoration(
                labelText: 'Street / Purok (optional)',
                hintText: 'Purok 3, Sitio Riverside',
                border: OutlineInputBorder(),
                helperText: 'Optional.',
              ),
              onChanged: _emitStreet,
            ),
          ],
        );
      },
    );
  }

  Widget _readOnlyLocation(
    BuildContext context,
    TrinidadLocationCatalog catalog,
  ) {
    final TrinidadLocation? value = widget.value;
    final String barangay = catalog.containsBarangay(value?.barangay)
        ? value!.barangay!
        : (widget.legacyAddress?.trim().isNotEmpty == true
              ? widget.legacyAddress!.trim()
              : 'Not provided');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _fixedField(label: 'Province', value: catalog.provinceLabel),
        const SizedBox(height: AppSpacing.md),
        _fixedField(label: 'Municipality', value: catalog.municipality),
        const SizedBox(height: AppSpacing.md),
        _fixedField(label: 'Barangay', value: barangay),
        if (value?.streetPurok.trim().isNotEmpty == true) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _fixedField(label: 'Street / Purok', value: value!.streetPurok),
        ],
      ],
    );
  }

  Widget _fixedField({required String label, required String value}) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizes.controlHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(value, softWrap: true)),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BarangayPickerSheet extends StatefulWidget {
  const _BarangayPickerSheet({
    required this.barangays,
    required this.selectedBarangay,
    required this.allowClear,
  });

  final List<String> barangays;
  final String? selectedBarangay;
  final bool allowClear;

  @override
  State<_BarangayPickerSheet> createState() => _BarangayPickerSheetState();
}

class _BarangayPickerSheetState extends State<_BarangayPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  late final ScrollController _resultsController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final int selectedIndex = widget.barangays.indexOf(
      widget.selectedBarangay ?? '',
    );
    _resultsController = ScrollController(
      initialScrollOffset: selectedIndex < 0 ? 0 : selectedIndex * 60.0,
    );
    if (selectedIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_resultsController.hasClients) return;
        final ScrollPosition position = _resultsController.position;
        _resultsController.jumpTo(
          (selectedIndex * 60.0)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble(),
        );
      });
    }
  }

  List<String> get _matchingBarangays {
    final String query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.barangays;

    return widget.barangays
        .where((String name) => name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  String get _countLabel {
    final int count = _matchingBarangays.length;
    if (_query.trim().isEmpty) {
      return '$count barangays available';
    }
    return '$count ${count == 1 ? 'barangay' : 'barangays'} found';
  }

  @override
  void dispose() {
    _resultsController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_resultsController.hasClients) {
        _resultsController.jumpTo(_resultsController.position.minScrollExtent);
      }
    });
  }

  void _close() => Navigator.of(context).pop();

  void _select(String value) => Navigator.of(context).pop(value);

  Widget _option({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? leadingIcon,
  }) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: selected ? AppColors.primarySurface : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.minTouchTarget + 8,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: <Widget>[
                if (leadingIcon != null) ...<Widget>[
                  Icon(
                    leadingIcon,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? AppColors.primary
                          : theme.colorScheme.onSurface,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> matches = _matchingBarangays;
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final double screenHeight = MediaQuery.sizeOf(context).height;
    final double maxSheetHeight = screenHeight * (bottomInset > 0 ? 0.9 : 0.82);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    key: trinidadBarangayDragHandleKey,
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Select Barangay',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            'Choose your barangay',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _close,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: AppSizes.minTouchTarget,
                        height: AppSizes.minTouchTarget,
                      ),
                      alignment: Alignment.topRight,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  constraints: const BoxConstraints(
                    minHeight: AppSizes.controlHeight,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.search,
                        size: 22,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          key: trinidadBarangaySearchFieldKey,
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onChanged: _onSearchChanged,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText: 'Search barangay...',
                            filled: false,
                            fillColor: Colors.transparent,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_query.isNotEmpty)
                        IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close),
                        )
                      else
                        const SizedBox(width: AppSpacing.xs),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _countLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (widget.allowClear) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  _option(
                    label: 'No barangay selected',
                    selected: widget.selectedBarangay == null,
                    leadingIcon: Icons.remove_circle_outline,
                    onTap: () => _select(''),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.xs),
                ],
                if (matches.isEmpty)
                  const SizedBox(
                    height: 112,
                    child: Center(child: Text('No barangays found')),
                  )
                else
                  Flexible(
                    fit: FlexFit.loose,
                    child: ListView.separated(
                      key: trinidadBarangayResultsKey,
                      controller: _resultsController,
                      primary: false,
                      shrinkWrap: true,
                      itemCount: matches.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.xxs),
                      itemBuilder: (BuildContext context, int index) {
                        final String barangay = matches[index];
                        return _option(
                          label: barangay,
                          selected: barangay == widget.selectedBarangay,
                          onTap: () => _select(barangay),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
