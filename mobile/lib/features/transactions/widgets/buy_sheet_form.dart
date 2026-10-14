import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/listing.dart';
import '../../../models/transaction.dart';
import '../../../repositories/transaction_repository.dart';

/// The quantity selector and create call inside [BuySheet].
///
/// Stateful so the sheet shell stays a cheap layout widget. The quantity
/// feeds the create call only — no live total is shown anywhere.
class BuySheetForm extends StatefulWidget {
  const BuySheetForm({required this.listing, required this.repository, super.key});

  final Listing listing;
  final TransactionRepository repository;

  @override
  State<BuySheetForm> createState() => _BuySheetFormState();
}

class _BuySheetFormState extends State<BuySheetForm> {
  late int _quantity;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _quantity = 1;
  }

  int get _maxQuantity =>
      widget.listing.quantity < 1 ? 1 : widget.listing.quantity;

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    // Confirm before creating: the record starts `pending` and the only exit
    // currently reachable is an irreversible cancel.
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Create transaction?'),
        content: Text(
          'You are requesting $_quantity × ${widget.listing.title}. '
          'The asking price is '
          '${AppFormatters.formatMoney(widget.listing.askingPrice) ?? widget.listing.askingPrice} '
          'per head. The final amount is set by the server.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final Transaction created = await widget.repository.create(
        listingId: widget.listing.id,
        quantity: _quantity,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(created);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = error.kind == ApiErrorKind.notFound
            ? 'This listing is no longer available.'
            : error.message;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Quantity', style: theme.textTheme.titleSmall),
            const Spacer(),
            IconButton(
              onPressed: _submitting || _quantity <= 1
                  ? null
                  : () => setState(() => _quantity--),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 48,
              child: Text(
                '$_quantity',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              onPressed: _submitting || _quantity >= _maxQuantity
                  ? null
                  : () => setState(() => _quantity++),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create transaction'),
          ),
        ),
      ],
    );
  }
}
