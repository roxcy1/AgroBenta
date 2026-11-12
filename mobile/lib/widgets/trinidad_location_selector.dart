import 'package:flutter/material.dart';

import 'field_label.dart';
import '../core/theme/app_spacing.dart';
import '../features/trinidad_location/state/trinidad_location_controller.dart';
import '../features/trinidad_location/state/trinidad_location_scope.dart';
import '../features/trinidad_location/state/trinidad_location_state.dart';
import '../models/trinidad_location.dart';

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
            decoration: InputDecoration(label: FieldLabel('Barangay')),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: AppSpacing.sm),
                Text('Loading Trinidad barangays...'),
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
            DropdownButtonFormField<String>(
              icon: const FieldDropdownIcon(),
              key: ValueKey<String>(
                'trinidad-barangay-${dropdownValue ?? 'unset'}',
              ),
              initialValue: dropdownValue,
              isExpanded: true,
              decoration: const InputDecoration(
                label: FieldLabel('Barangay'),
                errorMaxLines: 2,
              ),
              items: <DropdownMenuItem<String>>[
                if (!widget.isRequired)
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('No barangay selected'),
                  ),
                ...catalog.barangays.map(
                  (String barangay) => DropdownMenuItem<String>(
                    value: barangay,
                    child: Text(barangay),
                  ),
                ),
              ],
              onChanged: widget.enabled && !widget.readOnly
                  ? _selectBarangay
                  : null,
              validator: (String? value) => _validateBarangay(value, catalog),
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
                label: FieldLabel('Street / Purok (optional)'),
                hintText: 'Purok 3, Sitio Riverside',
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
    return InputDecorator(
      decoration: InputDecoration(
        label: FieldLabel(label),
        suffixIcon: const FieldIcon(Icon(Icons.lock_outline)),
      ),
      child: Text(value),
    );
  }
}
