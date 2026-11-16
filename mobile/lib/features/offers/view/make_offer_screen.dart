import 'package:flutter/material.dart';

import '../../../core/theme/app_input_border.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/inquiry.dart';
import '../../../models/offer.dart';
import '../../../models/received_inquiry.dart';
import '../../marketplace/state/marketplace_scope.dart';
import '../../../widgets/field_label.dart';
import '../../../widgets/notice_banner.dart';
import '../state/make_offer_controller.dart';
import '../state/offer_scope.dart';
import '../state/offer_state.dart';

/// The seller's structured purchase-offer form for a received inquiry.
///
/// An offer is always created from an existing inquiry: the inquiry supplies
/// the buyer and the listing, so this screen sends only `inquiry_id`,
/// `listing_id`, the proposed amount and the terms. The seller, the buyer, the
/// status and the inquiry's original preferences are all server-provided.
///
/// The buyer, the livestock listing and the listed price are read-only — they
/// are facts, not choices. The seller edits the final price, the proposed
/// pickup date, the payment method, the collection method and an optional note;
/// every editable field is prefilled from the buyer's inquiry so "keep the
/// buyer's preference" is the default.
///
/// Two ways in, both from the server's own records:
///
///  * [MakeOfferScreen] — the seller's Received Inquiries list.
///  * [MakeOfferScreen.forConversation] — a chat thread, using
///    `ConversationResource.eligible_inquiry`.
///
/// The controller is owned by this route. Popping returns `true` when an offer
/// was created so the inbox (or chat panel) can refresh.
class MakeOfferScreen extends StatefulWidget {
  /// Opens the form from a received inquiry.
  factory MakeOfferScreen({required ReceivedInquiry inquiry, Key? key}) {
    return MakeOfferScreen._(
      inquiryId: inquiry.id,
      listingId: inquiry.listing?.id,
      buyerName: inquiry.buyer?.name,
      listingTitle: inquiry.listing?.title,
      askingPrice: inquiry.listing?.askingPrice,
      photoUrl: inquiry.listing?.photoUrl,
      initialPaymentMethod: inquiry.paymentMethod,
      initialCollectionMethod: inquiry.collectionMethod,
      initialPickupDate: inquiry.preferredSchedule,
      requestedQuantity: inquiry.requestedQuantity,
      listingAvailableQuantity: inquiry.listing?.availableQuantity,
      inventoryReconciliationRequired:
          inquiry.listing?.inventoryReconciliationRequired ?? false,
      key: key,
    );
  }

  /// Opens the form from a conversation, using the server's eligible inquiry.
  factory MakeOfferScreen.forConversation({
    required int inquiryId,
    required int listingId,
    required String buyerName,
    String? listingTitle,
    String? askingPrice,
    String? photoUrl,
    InquiryPaymentMethod? paymentMethod,
    InquiryCollectionMethod? collectionMethod,
    DateTime? preferredSchedule,
    int requestedQuantity = 1,
    int? listingAvailableQuantity,
    bool inventoryReconciliationRequired = false,
    Key? key,
  }) {
    return MakeOfferScreen._(
      inquiryId: inquiryId,
      listingId: listingId,
      buyerName: buyerName,
      listingTitle: listingTitle,
      askingPrice: askingPrice,
      photoUrl: photoUrl,
      initialPaymentMethod: paymentMethod,
      initialCollectionMethod: collectionMethod,
      initialPickupDate: preferredSchedule,
      requestedQuantity: requestedQuantity,
      listingAvailableQuantity: listingAvailableQuantity,
      inventoryReconciliationRequired: inventoryReconciliationRequired,
      key: key,
    );
  }

  const MakeOfferScreen._({
    required this.inquiryId,
    required this.listingId,
    required this.buyerName,
    required this.listingTitle,
    this.askingPrice,
    this.photoUrl,
    this.initialPaymentMethod,
    this.initialCollectionMethod,
    this.initialPickupDate,
    this.requestedQuantity = 1,
    this.listingAvailableQuantity,
    this.inventoryReconciliationRequired = false,
    super.key,
  });

  final int inquiryId;
  final int? listingId;
  final String? buyerName;
  final String? listingTitle;
  final String? askingPrice;
  final String? photoUrl;

  /// The buyer's original preferences, used as the initial values.
  final InquiryPaymentMethod? initialPaymentMethod;
  final InquiryCollectionMethod? initialCollectionMethod;
  final DateTime? initialPickupDate;
  final int requestedQuantity;
  final int? listingAvailableQuantity;
  final bool inventoryReconciliationRequired;

  @override
  State<MakeOfferScreen> createState() => _MakeOfferScreenState();
}

class _MakeOfferScreenState extends State<MakeOfferScreen> {
  late final MakeOfferController _controller;
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  late InquiryPaymentMethod? _paymentMethod = widget.initialPaymentMethod;
  late InquiryCollectionMethod? _collectionMethod =
      widget.initialCollectionMethod;
  late int _proposedQuantity = widget.requestedQuantity;

  int get _maximumProposedQuantity {
    if (widget.inventoryReconciliationRequired ||
        _controller.state.inventoryReconciliationRequired ||
        _controller.state.listingUnavailable) {
      return 0;
    }
    final int? available =
        _controller.state.refreshedAvailableQuantity ??
        widget.listingAvailableQuantity;
    if (available == null) return widget.requestedQuantity;
    if (available < 0) return 0;
    return available < widget.requestedQuantity
        ? available
        : widget.requestedQuantity;
  }

  /// Earliest date the seller may propose: tomorrow. The backend also refuses
  /// past dates, so the picker and the server agree.
  static DateTime get _tomorrow {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  /// The buyer's preferred date when it is still selectable; otherwise the
  /// form starts on tomorrow. [widget.initialPickupDate] is kept untouched so
  /// the change marker still compares against the buyer's original preference.
  static DateTime _initialPickup(DateTime? preferred) {
    if (preferred == null) {
      return _tomorrow;
    }
    final DateTime day = DateTime(
      preferred.year,
      preferred.month,
      preferred.day,
    );
    return day.isBefore(_tomorrow) ? _tomorrow : day;
  }

  late DateTime? _pickupDate = _initialPickup(widget.initialPickupDate);

  @override
  void initState() {
    super.initState();
    _controller = MakeOfferController(
      OfferScope.readOf(context),
      marketplace: MarketplaceScope.readOf(context).repository,
    );
    // The listing price is per head while the offer amount is the total for
    // this offer's quantity. Prefill the product; the seller may edit it.
    final double? askingPrice = widget.askingPrice == null
        ? null
        : AppFormatters.parseDecimal(widget.askingPrice!);
    _amount.text = askingPrice == null
        ? ''
        : (askingPrice * widget.requestedQuantity).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime first = _tomorrow;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _pickupDate ?? first,
      firstDate: first,
      lastDate: first.add(const Duration(days: 90)),
      helpText: 'Proposed pickup date',
    );
    if (picked != null && mounted) {
      setState(() => _pickupDate = picked);
    }
  }

  /// True when the chosen pickup date differs from the buyer's original one.
  bool get _pickupChanged {
    final DateTime? original = widget.initialPickupDate;
    final DateTime? current = _pickupDate;
    if (original == null || current == null) {
      return original != current;
    }
    return original.year != current.year ||
        original.month != current.month ||
        original.day != current.day;
  }

  Future<void> _submit() async {
    final String buyerLabel = widget.buyerName ?? 'the buyer';
    final int? listingId = widget.listingId;
    if (listingId == null) {
      return;
    }

    final Offer? created = await _controller.submit(
      inquiryId: widget.inquiryId,
      listingId: listingId,
      amount: _amount.text,
      proposedQuantity: _proposedQuantity,
      pickupDate: _pickupDate,
      paymentMethod: _paymentMethod,
      collectionMethod: _collectionMethod,
      note: _note.text,
    );
    if (created == null || !mounted) {
      return;
    }

    final String amount =
        AppFormatters.formatMoney(created.proposedAmount) ??
        created.proposedAmount;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Offer sent'),
        content: Text(
          '$amount is now visible to $buyerLabel in your conversation. '
          'It covers ${created.proposedQuantity} ${created.proposedQuantity == 1 ? 'animal' : 'animals'} and stays pending until the buyer accepts or declines it.',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String buyerLabel = widget.buyerName ?? 'Unknown buyer';
    final String listingLabel =
        widget.listingTitle ?? 'Listing no longer available';
    final String? askingPrice = widget.askingPrice == null
        ? null
        : AppFormatters.formatMoney(widget.askingPrice!) ?? widget.askingPrice;

    return Scaffold(
      appBar: AppBar(title: const Text('Make an Offer')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final MakeOfferState state = _controller.state;
            final bool canSubmit =
                widget.listingId != null &&
                !state.isSubmitting &&
                !widget.inventoryReconciliationRequired &&
                !state.inventoryReconciliationRequired &&
                !state.listingUnavailable &&
                _maximumProposedQuantity > 0 &&
                _proposedQuantity <= _maximumProposedQuantity;

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              children: <Widget>[
                if (widget.inventoryReconciliationRequired ||
                    state.inventoryReconciliationRequired) ...<Widget>[
                  const NoticeBanner(
                    accent: AppColors.warning,
                    icon: Icons.inventory_2_outlined,
                    message: 'Inventory reconciliation is required. You cannot make an offer yet.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                ] else if (state.listingUnavailable ||
                    (state.refreshedAvailableQuantity == 0)) ...<Widget>[
                  const NoticeBanner(
                    accent: AppColors.warning,
                    icon: Icons.inventory_2_outlined,
                    message: 'This listing is no longer available for offers.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                ] else if (state.refreshedAvailableQuantity != null &&
                    _proposedQuantity > _maximumProposedQuantity) ...<Widget>[
                  NoticeBanner(
                    accent: AppColors.warning,
                    icon: Icons.info_outline,
                    message: 'Only ${state.refreshedAvailableQuantity} animals remain. Reduce the offer quantity to continue.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _ListingPhoto(url: widget.photoUrl),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                listingLabel,
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                buyerLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              if (askingPrice != null) ...<Widget>[
                                const SizedBox(height: 2),
                                Text(
                                  'Listed price: $askingPrice',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Agreed quantity', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '$_proposedQuantity ${_proposedQuantity == 1 ? 'animal' : 'animals'}',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Reduce quantity',
                          onPressed: state.isSubmitting || _proposedQuantity <= 1
                              ? null
                              : () => setState(() => _proposedQuantity--),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Increase quantity',
                          onPressed: state.isSubmitting ||
                                  _proposedQuantity >= _maximumProposedQuantity
                              ? null
                              : () => setState(() => _proposedQuantity++),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  'Buyer requested ${widget.requestedQuantity}. You can offer no more than requested or currently available stock.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Total offer amount', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _amount,
                  autofocus: true,
                  enabled: !state.isSubmitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    prefixText: '₱ ',
                    hintText: '0.00',
                    contentPadding: AppInputs.plainPadding,
                    errorText: state.amountErrorMessage,
                    helperText:
                        'Total for $_proposedQuantity ${_proposedQuantity == 1 ? 'animal' : 'animals'}. The listing\'s asking price is per head and remains unchanged.',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _TermRow(
                  label: 'Pickup date',
                  value: _pickupDate == null
                      ? 'Buyer did not choose one'
                      : AppFormatters.formatDate(_pickupDate),
                  onPressed: state.isSubmitting ? null : _pickDate,
                  changed: _pickupChanged,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<InquiryPaymentMethod>(
                  icon: const FieldDropdownIcon(),
                  initialValue: _paymentMethod,
                  decoration: const InputDecoration(
                    label: FieldLabel('Payment method'),
                  ),
                  items: InquiryPaymentMethod.values
                      .map(
                        (InquiryPaymentMethod method) =>
                            DropdownMenuItem<InquiryPaymentMethod>(
                              value: method,
                              child: Text(method.label),
                            ),
                      )
                      .toList(growable: false),
                  onChanged: state.isSubmitting
                      ? null
                      : (InquiryPaymentMethod? value) =>
                            setState(() => _paymentMethod = value),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<InquiryCollectionMethod>(
                  icon: const FieldDropdownIcon(),
                  initialValue: _collectionMethod,
                  decoration: const InputDecoration(
                    label: FieldLabel('Collection method'),
                  ),
                  items: InquiryCollectionMethod.values
                      .map(
                        (InquiryCollectionMethod method) =>
                            DropdownMenuItem<InquiryCollectionMethod>(
                              value: method,
                              child: Text(method.label),
                            ),
                      )
                      .toList(growable: false),
                  onChanged: state.isSubmitting
                      ? null
                      : (InquiryCollectionMethod? value) =>
                            setState(() => _collectionMethod = value),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _note,
                  enabled: !state.isSubmitting,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    label: FieldLabel('Note (optional)'),
                    hintText:
                        'Anything the buyer should know about this offer.',
                  ),
                ),
                if (state.errorMessage != null &&
                    state.amountErrorMessage == null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    state.errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  height: AppSizes.controlHeight,
                  child: FilledButton(
                    onPressed: canSubmit ? _submit : null,
                    child: state.isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send offer'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One read-mostly term row: the label, the current value, a change marker and
/// an action that edits it.
class _TermRow extends StatelessWidget {
  const _TermRow({
    required this.label,
    required this.value,
    required this.onPressed,
    required this.changed,
  });

  final String label;
  final String value;
  final VoidCallback? onPressed;
  final bool changed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 120,
              child: Text(label, style: theme.textTheme.labelMedium),
            ),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: changed ? AppColors.primary : AppColors.text,
                  fontWeight: changed ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (changed)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: Text(
                  'changed',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            Icon(
              Icons.edit_outlined,
              size: 18,
              color: onPressed == null
                  ? AppColors.border
                  : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// The listing thumbnail in the offer form: the real photo when one exists,
/// otherwise the same livestock glyph the rest of the app uses.
class _ListingPhoto extends StatelessWidget {
  const _ListingPhoto({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final String? source = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        width: 72,
        height: 72,
        child: source == null || source.isEmpty
            ? Container(
                color: AppColors.primarySurface,
                child: const Icon(
                  Icons.pets_outlined,
                  color: AppColors.textSecondary,
                ),
              )
            : Image.network(
                source,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.primarySurface,
                  child: const Icon(
                    Icons.pets_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
      ),
    );
  }
}
