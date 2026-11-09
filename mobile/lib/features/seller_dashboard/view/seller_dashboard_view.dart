import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/seller_activity.dart';
import '../../../models/seller_dashboard.dart';
import '../../../repositories/seller_activity_repository.dart';
import '../../../widgets/paged_list_state_views.dart';
import '../state/seller_activity_controller.dart';
import '../state/seller_dashboard_controller.dart';
import '../state/seller_dashboard_scope.dart';
import '../state/seller_dashboard_state.dart';
import '../widgets/seller_activity_tile.dart';

/// The seller dashboard shown on Seller Home.
///
/// Every value comes from `GET /seller/dashboard`, resolved from the token.
/// Loading, empty, error and refresh states are rendered from that response;
/// nothing is estimated.
class SellerDashboardView extends StatefulWidget {
  const SellerDashboardView({
    required this.onOpenListings,
    required this.onOpenTransactions,
    required this.onAddListing,
    this.activityRepository,
    this.onOpenOffer,
    this.onOpenTransaction,
    this.onSeeAllActivities,
    super.key,
  });

  final VoidCallback onOpenListings;
  final VoidCallback onOpenTransactions;

  /// Opens the existing create-listing form; the dashboard refreshes when the
  /// returned future completes.
  final Future<void> Function() onAddListing;

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
  SellerActivityController? _activity;

  @override
  void initState() {
    super.initState();
    _controller = SellerDashboardController(
      SellerDashboardScope.readOf(context),
    );
    _controller.loadInitial();

    final SellerActivityRepository? activities = widget.activityRepository;
    if (activities != null) {
      _activity = SellerActivityController(activities)..load();
    }
  }

  @override
  void dispose() {
    _activity?.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Future.wait<void>(<Future<void>>[
      _controller.refresh(),
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
          if (_activity != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            _RecentActivitySection(
              controller: _activity!,
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
    required this.onOpenTransactions,
  });

  final SellerDashboard dashboard;
  final VoidCallback onOpenListings;
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

/// The latest genuine seller events, newest first, capped at five.
///
/// Each row navigates only when its context identifies an existing record:
/// listing events open My Listings, and transaction events open the
/// transaction detail (or the Transactions tab when the id is missing). No row
/// is ever routed to a guessed record.
class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({
    required this.controller,
    required this.onOpenListings,
    required this.onOpenTransactions,
    required this.onOpenOffer,
    required this.onOpenTransaction,
    required this.onSeeAll,
  });

  final SellerActivityController controller;
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
      // Inquiries are delivered as messages now (§8.2): there is no seller
      // inbox to open, so activity rows have nothing to navigate to here.
      return null;
    }

    if (action.startsWith('offer')) {
      final int? buyerId = activity.buyerId;
      if (buyerId != null && onOpenOffer != null) {
        return () => onOpenOffer!(buyerId, activity.transactionId);
      }
      return null;
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
