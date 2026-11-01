import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/inquiry.dart';
import '../../../models/offer.dart';
import '../../../models/received_inquiry.dart';
import '../state/make_offer_controller.dart';
import '../state/offer_scope.dart';
import '../state/offer_state.dart';

/// The seller's form for proposing a final price on a received inquiry.
///
/// An offer is always created from an existing inquiry: the inquiry supplies
/// the buyer and the listing, so this screen sends only `inquiry_id`,
/// `listing_id` and the proposed amount. The seller, the buyer and the
/// `pending` status are all server-derived.
///
/// The controller is owned by this route. Popping returns `true` when an offer
/// was created so the seller's inbox can refresh.
class MakeOfferScreen extends StatefulWidget {
  const MakeOfferScreen({required this.inquiry, super.key});

  final ReceivedInquiry inquiry;

  @override
  State<MakeOfferScreen> createState() => _MakeOfferScreenState();
}

class _MakeOfferScreenState extends State<MakeOfferScreen> {
  late final MakeOfferController _controller;
  final TextEditingController _amount = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = MakeOfferController(OfferScope.readOf(context));
  }

  @override
  void dispose() {
    _amount.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final InquiryBuyer? buyer = widget.inquiry.buyer;
    final InquiryListing? listing = widget.inquiry.listing;
    if (buyer == null || listing == null) {
      return;
    }

    final Offer? created = await _controller.submit(
      inquiryId: widget.inquiry.id,
      listingId: listing.id,
      amount: _amount.text,
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
          '$amount is now visible to ${buyer.name} in your conversation. '
          'It stays pending until the buyer accepts or declines it.',
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
    final InquiryBuyer? buyer = widget.inquiry.buyer;
    final InquiryListing? listing = widget.inquiry.listing;

    return Scaffold(
      appBar: AppBar(title: const Text('Make an Offer')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final MakeOfferState state = _controller.state;
            final bool canSubmit =
                buyer != null && listing != null && !state.isSubmitting;

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          buyer?.name ?? 'Unknown buyer',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.pets_outlined,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            Expanded(
                              child: Text(
                                listing?.title ?? 'Listing no longer available',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Offer amount', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _amount,
                  autofocus: true,
                  enabled: !state.isSubmitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (canSubmit) {
                      _submit();
                    }
                  },
                  decoration: InputDecoration(
                    prefixText: '₱ ',
                    hintText: '0.00',
                    errorText: state.amountErrorMessage,
                    helperText:
                        'The final price you are proposing for this inquiry. '
                        'The listing\'s asking price is unchanged.',
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
