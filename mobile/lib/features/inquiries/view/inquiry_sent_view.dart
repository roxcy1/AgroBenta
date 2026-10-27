import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/inquiry.dart';
import '../../../models/listing.dart';
import '../../../widgets/section_card.dart';
import '../widgets/inquiry_listing_card.dart';

/// The Inquiry Sent confirmation — shown once the server has confirmed
/// persistence (design spec `AgroBenta_Inquiry_Sent_DESIGN.md`).
///
/// Every value on this screen comes from one of two real sources: the
/// [Listing] the buyer asked about, and the [Inquiry] the create response
/// returned. Nothing is sample data, nothing is invented, and the view claims
/// nothing the response does not prove — no notification promise, no delivery
/// guarantee, no fabricated status.
///
/// ## The status card is display-only
///
/// The backend exposes no buyer-facing inquiry-read endpoint
/// (`GET /api/inquiries*` is admin-only) and `MobileInquiryResource` omits the
/// server's `status` column deliberately — the open/responded/closed enum is
/// an admin triage bookmark, not a buyer-facing workflow. The card therefore
/// describes the workflow position the buyer is factually in the moment the
/// create response arrives — sent, not yet answered — using only theme tokens.
/// It is never driven by, and must never grow, a server status field
/// (mobile/AGENTS.md §B; GAP-19).
///
/// ## View Inquiry is rendered disabled
///
/// There is no inquiry-details destination or endpoint for a buyer. The button
/// is kept visible with an honest caption rather than faking a route
/// (design spec §4.1; GAP-19).
class InquirySentView extends StatelessWidget {
  const InquirySentView({
    required this.listing,
    required this.inquiry,
    required this.onBackToBrowse,
    super.key,
  });

  /// The listing that was asked about — drives the listing summary card.
  final Listing listing;

  /// The server-confirmed inquiry — the single source of truth for the
  /// "Your Inquiry" summary. No read endpoint exists to refresh it.
  final Inquiry inquiry;

  /// Returns to the buyer shell's Browse destination.
  final VoidCallback onBackToBrowse;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SuccessHeader(theme: theme),
              const SizedBox(height: AppSpacing.lg),
              InquiryListingCard(listing: listing),
              const SizedBox(height: AppSpacing.md),
              _YourInquiryCard(inquiry: inquiry),
              const SizedBox(height: AppSpacing.md),
              const _StatusCard(),
              const SizedBox(height: AppSpacing.lg),
              // Disabled: there is no buyer endpoint to fetch a saved inquiry
              // and no details screen. The caption states the gap honestly
              // rather than leaving a dead button unexplained (GAP-19).
              FilledButton(
                onPressed: null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text('View Inquiry'),
                    const SizedBox(width: AppSpacing.xxs),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Viewing a saved inquiry is not available in the app yet.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: onBackToBrowse,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Back to Browse'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pale-green check circle, the heading, and the supporting line.
class _SuccessHeader extends StatelessWidget {
  const _SuccessHeader({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: AppColors.primarySurface,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 36,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Your inquiry has been sent to the seller.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'The seller can review your inquiry and reply through in-app '
          'messages.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// "Your Inquiry": the actual submitted values the create response echoed
/// back. A field the buyer left empty is omitted rather than filled with a
/// placeholder — the summary reports what was stored, nothing else.
class _YourInquiryCard extends StatelessWidget {
  const _YourInquiryCard({required this.inquiry});

  final Inquiry inquiry;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Your Inquiry',
      children: <Widget>[
        if (inquiry.subject != null && inquiry.subject!.trim().isNotEmpty)
          _SummaryRow(
            icon: Icons.label_outline,
            label: 'Subject',
            value: inquiry.subject!,
          ),
        _SummaryRow(
          icon: Icons.forum_outlined,
          label: 'Message',
          value: inquiry.message,
        ),
        if (inquiry.purchaseInterest != null)
          _SummaryRow(
            icon: Icons.shopping_cart_outlined,
            label: 'Interested in purchasing?',
            value: inquiry.purchaseInterest! ? 'Yes' : 'No',
          ),
        if (inquiry.transactionMethod != null)
          _SummaryRow(
            icon: Icons.swap_horiz_outlined,
            label: 'Transaction preference',
            value: inquiry.transactionMethod!.label,
          ),
        if (inquiry.deliveryFee != null)
          _SummaryRow(
            icon: Icons.payments_outlined,
            label: 'Delivery fee',
            value:
                AppFormatters.formatMoney(inquiry.deliveryFee) ??
                inquiry.deliveryFee!,
          ),
        if (inquiry.contactMethod != null)
          _SummaryRow(
            icon: Icons.chat_bubble_outline,
            label: 'Preferred contact method',
            value: inquiry.contactMethod!.label,
          ),
        if (inquiry.preferredSchedule != null)
          _SummaryRow(
            icon: Icons.event_outlined,
            label: 'Preferred schedule',
            value: AppFormatters.formatDate(inquiry.preferredSchedule),
          ),
      ],
    );
  }
}

/// One label/value row in the confirmation summary. The value wraps; it is
/// never truncated, because a message the buyer just wrote must stay readable
/// and there is no details screen to show the rest (design spec §3.4).
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The pale-amber "Awaiting seller response" panel.
///
/// "Awaiting seller response" is the factual workflow position at the moment
/// the create response arrives: the inquiry is stored and unanswered. It is a
/// fixed, honest sentence — not a status read from the server, and not part of
/// any client-side status model (see the class doc on [InquirySentView]).
class _StatusCard extends StatelessWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.schedule,
              size: 22,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Inquiry Status', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Awaiting seller response',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Your inquiry is saved. The seller can respond through the '
                  'app.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
