import 'package:flutter/material.dart';

import '../../../core/realtime/realtime_scope.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/received_inquiry.dart';
import '../../../models/seller_activity.dart';
import '../../../models/seller_dashboard.dart';
import '../../../repositories/inquiry_repository.dart';
import '../../../repositories/seller_activity_repository.dart';
import '../../../widgets/paged_list_state_views.dart';
import '../../inquiries/state/received_inquiries_controller.dart';
import '../../inquiries/state/received_inquiries_state.dart';
import '../state/seller_activity_controller.dart';
import '../state/seller_dashboard_controller.dart';
import '../state/seller_dashboard_scope.dart';
import '../state/seller_dashboard_state.dart';
import '../widgets/seller_activity_tile.dart';

/// The seller dashboard shown on Seller Home.
///
/// Every value comes from real seller-scoped endpoints:
/// `GET /seller/dashboard` for the summary, and — when a repository is supplied
/// — `GET /seller/inquiries` for the attention list. Loading, empty, error,
/// refresh and zero-count states are rendered from those responses; nothing is
/// estimated.
class SellerDashboardView extends StatefulWidget {
  const SellerDashboardView({
    required this.onOpenListings,
    required this.onOpenInquiries,
    required this.onOpenTransactions,
    required this.onAddListing,
    this.inquiriesRepository,
    this.activityRepository,
    this.onOpenOffer,
    this.onOpenTransaction,
    this.onSeeAllActivities,
    super.key,
  });

  final VoidCallback onOpenListings;
  final VoidCallback onOpenInquiries;
  final VoidCallback onOpenTransactions;

  /// Opens the existing create-listing form; the dashboard refreshes when the
  /// returned future completes.
  final Future<void> Function() onAddListing;

  /// Optional so the view can be mounted without the inquiry scope (tests, or
  /// a future host that does not show attention items). When null the section
  /// is omitted rather than showing invented rows.
  final InquiryRepository? inquiriesRepository;

  /// Optional seller activity repository; the section is omitted when null.
  final SellerActivityRepository? activityRepository;

  /// Opens the existing buyer conversation for an offer event. The second
  /// argument is the transaction id when the offer was accepted.
  final void Function(int buyerId, int? transactionId)? onOpenOffer;

  /// Opens the existing transaction detail screen.
  final ValueChanged<int>? onOpenTransaction;

  /// Opens the All Activities screen; the section's heading shows See All only
  /// when this is supplied.
  final VoidCallback? onSeeAllActivities;

  @override
  State<SellerDashboardView> createState() => _SellerDashboardViewState();
}

class _SellerDashboardViewState extends State<SellerDashboardView> {
  late final SellerDashboardController _controller;
  ReceivedInquiriesController? _attention;
  SellerActivityController? _activity;

  @override
  void initState() {
    super.initState();
    final realtime = RealtimeScope.maybeOf(context);
    _controller = SellerDashboardController(
      SellerDashboardScope.readOf(context),
      realtimeEvents: realtime?.events,
      connection: realtime?.connected,
    );
    _controller.loadInitial();

    final InquiryRepository? repository = widget.inquiriesRepository;
    if (repository != null) {
      _attention = ReceivedInquiriesController(
        repository,
        realtimeEvents: realtime?.events,
        connection: realtime?.connected,
      )..loadInitial();
    }

    final SellerActivityRepository? activities = widget.activityRepository;
    if (activities != null) {
      _activity = SellerActivityController(activities)..load();
    }
  }

  @override
  void dispose() {
    _activity?.dispose();
    _attention?.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Future.wait<void>(<Future<void>>[
      _controller.refresh(),
      if (_attention != null) _attention!.refresh(),
      if (_activity != null) _activity!.refresh(),
    ]);
  }

  Future<void> _addListing() async {
    await widget.onAddListing();
    if (mounted) {
      await _controller.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable?>[
          _controller,
          _attention,
          _activity,
        ].whereType<Listenable>().toList(growable: false)),
        builder: (BuildContext context, Widget? child) {
          return _buildBody(context, _controller.state);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, SellerDashboardState state) {
    final ThemeData theme = Theme.of(context);
    final SellerDashboard? dashboard = state.dashboard;

    if (state.status == SellerDashboardStatus.failed) {
      return _scroll(
        child: _DashboardErrorCard(
          message: state.errorMessage ?? 'Could not load your dashboard.',
          onRetry: _controller.retry,
        ),
      );
    }

    if (dashboard == null) {
      return _scroll(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.xxl,
          AppSpacing.screenGutter,
          AppSpacing.xl,
        ),
        child: Center(
          child: Column(
            children: <Widget>[
              const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Loading your dashboard...',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _scroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.refreshErrorMessage != null) ...<Widget>[
            PagedListRefreshNotice(
              message: state.refreshErrorMessage!,
              onRetry: _controller.refresh,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          SizedBox(
            height: AppSizes.controlHeight,
            child: FilledButton.icon(
              onPressed: _addListing,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add listing'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _SummaryGrid(
            dashboard: dashboard,
            onOpenListings: widget.onOpenListings,
            onOpenInquiries: widget.onOpenInquiries,
            onOpenTransactions: widget.onOpenTransactions,
          ),
          if (!dashboard.hasActivity) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No seller activity yet. Create your first listing to start '
              'receiving inquiries and recording transactions.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (_attention != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            _AttentionSection(
              controller: _attention!,
              onOpenInquiries: widget.onOpenInquiries,
            ),
          ],
          if (_activity != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            _RecentActivitySection(
              controller: _activity!,
              onOpenInquiries: widget.onOpenInquiries,
              onOpenListings: widget.onOpenListings,
              onOpenTransactions: widget.onOpenTransactions,
              onOpenOffer: widget.onOpenOffer,
              onOpenTransaction: widget.onOpenTransaction,
              onSeeAll: widget.onSeeAllActivities,
            ),
          ],
        ],
      ),
    );
  }

  Widget _scroll({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(
      AppSpacing.screenGutter,
      AppSpacing.xs,
      AppSpacing.screenGutter,
      AppSpacing.xl,
    ),
  }) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      child: child,
    );
  }
}

/// Active Listings, Inquiries, Ongoing Transactions and Completed Sales.
///
/// Two columns at every width, per the approved layout: the cards stay equal
/// sized and readable on a phone and on a tablet.
class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.dashboard,
    required this.onOpenListings,
    required this.onOpenInquiries,
    required this.onOpenTransactions,
  });

  final SellerDashboard dashboard;
  final VoidCallback onOpenListings;
  final VoidCallback onOpenInquiries;
  final VoidCallback onOpenTransactions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = AppSpacing.sm;
        final double width = (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            _SummaryTile(
              width: width,
              label: 'Active Listings',
              value: dashboard.listings.active,
              icon: Icons.storefront_outlined,
              onTap: onOpenListings,
            ),
            _SummaryTile(
              width: width,
              label: 'Inquiries',
              value: dashboard.inquiries.total,
              icon: Icons.mark_email_unread_outlined,
              onTap: onOpenInquiries,
            ),
            _SummaryTile(
              width: width,
              label: 'Ongoing Transactions',
              value: dashboard.transactions.pending,
              icon: Icons.swap_horiz_outlined,
              onTap: onOpenTransactions,
            ),
            _SummaryTile(
              width: width,
              label: 'Completed Sales',
              value: dashboard.transactions.completed,
              icon: Icons.task_alt_outlined,
              onTap: onOpenTransactions,
            ),
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final double width;
  final String label;
  final int value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$value',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
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

/// Up to three genuinely actionable inquiries (`can_make_offer` is true, which
/// the server defines as an open inquiry with no pending or accepted offer).
///
/// When nothing is actionable but inquiries exist, the same rows are shown
/// under a "Recent inquiries" label with no claim that action is required.
class _AttentionSection extends StatelessWidget {
  const _AttentionSection({
    required this.controller,
    required this.onOpenInquiries,
  });

  final ReceivedInquiriesController controller;
  final VoidCallback onOpenInquiries;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ReceivedInquiriesState state = controller.state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Needs Your Attention', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        if (state.status == ReceivedInquiriesStatus.failed)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Could not load inquiries.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: controller.loadInitial,
                child: const Text('Retry'),
              ),
            ],
          )
        else if (state.status == ReceivedInquiriesStatus.initial ||
            state.status == ReceivedInquiriesStatus.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          _attentionBody(theme, state),
      ],
    );
  }

  Widget _attentionBody(ThemeData theme, ReceivedInquiriesState state) {
    final List<ReceivedInquiry> actionable = state.inquiries
        .where((ReceivedInquiry inquiry) => inquiry.canMakeOffer)
        .take(3)
        .toList(growable: false);
    final bool isActionable = actionable.isNotEmpty;
    final List<ReceivedInquiry> shown = isActionable
        ? actionable
        : state.inquiries.take(3).toList(growable: false);

    if (shown.isEmpty) {
      return Text(
        'No inquiries yet.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final ReceivedInquiry inquiry in shown)
          _AttentionTile(inquiry: inquiry, onTap: onOpenInquiries),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onOpenInquiries,
            child: Text(
              isActionable ? 'View inquiries' : 'View recent inquiries',
            ),
          ),
        ),
      ],
    );
  }
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({required this.inquiry, required this.onTap});

  final ReceivedInquiry inquiry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String buyer = inquiry.buyer?.name ?? 'Unknown buyer';
    final String listing = inquiry.listing?.title ?? 'Listing no longer available';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(buyer, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      listing,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// The latest genuine seller events, newest first, capped at five.
///
/// Each row navigates only when its context identifies an existing record:
/// inquiry events open the inbox, offers open the buyer conversation (or the
/// inbox when the buyer id is missing), listing events open My Listings, and
/// transaction events open the transaction detail (or the Transactions tab when
/// the id is missing). No row is ever routed to a guessed record.
class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({
    required this.controller,
    required this.onOpenInquiries,
    required this.onOpenListings,
    required this.onOpenTransactions,
    required this.onOpenOffer,
    required this.onOpenTransaction,
    required this.onSeeAll,
  });

  final SellerActivityController controller;
  final VoidCallback onOpenInquiries;
  final VoidCallback onOpenListings;
  final VoidCallback onOpenTransactions;
  final void Function(int buyerId, int? transactionId)? onOpenOffer;
  final ValueChanged<int>? onOpenTransaction;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Recent Activity', style: theme.textTheme.titleMedium),
            ),
            if (onSeeAll != null)
              TextButton(onPressed: onSeeAll, child: const Text('See All')),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _body(theme),
      ],
    );
  }

  Widget _body(ThemeData theme) {
    final SellerActivityState state = controller.state;

    switch (state.status) {
      case SellerActivityStatus.initial:
      case SellerActivityStatus.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Center(
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case SellerActivityStatus.failed:
        return Row(
          children: <Widget>[
            Expanded(
              child: Text(
                state.errorMessage ?? 'Could not load recent activity.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(onPressed: controller.retry, child: const Text('Retry')),
          ],
        );
      case SellerActivityStatus.empty:
        return Text(
          'No recent activity yet.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        );
      case SellerActivityStatus.ready:
        final List<SellerActivity> shown = state.activities
            .take(5)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final SellerActivity activity in shown)
              SellerActivityTile(
                activity: activity,
                onTap: _actionFor(activity),
              ),
          ],
        );
    }
  }

  VoidCallback? _actionFor(SellerActivity activity) {
    final String action = activity.action;

    if (action.startsWith('inquiry')) {
      return onOpenInquiries;
    }

    if (action.startsWith('offer')) {
      final int? buyerId = activity.buyerId;
      if (buyerId != null && onOpenOffer != null) {
        return () => onOpenOffer!(buyerId, activity.transactionId);
      }
      return onOpenInquiries;
    }

    if (action.startsWith('listing')) {
      return onOpenListings;
    }

    if (action.startsWith('transaction')) {
      final int? id = activity.transactionId ?? activity.targetId;
      if (id != null && onOpenTransaction != null) {
        return () => onOpenTransaction!(id);
      }
      return onOpenTransactions;
    }

    return null;
  }
}

class _DashboardErrorCard extends StatelessWidget {
  const _DashboardErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: <Widget>[
            const Icon(
              Icons.cloud_off_outlined,
              size: 36,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Could not load your dashboard',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
