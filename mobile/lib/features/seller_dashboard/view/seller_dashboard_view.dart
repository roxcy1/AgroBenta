import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/seller_dashboard.dart';
import '../../../widgets/paged_list_state_views.dart';
import '../state/seller_dashboard_controller.dart';
import '../state/seller_dashboard_scope.dart';
import '../state/seller_dashboard_state.dart';

/// The seller dashboard shown on Seller Home.
///
/// Every number comes from `GET /seller/dashboard`. The view renders loading,
/// empty, error/retry, refresh-failure and ready states from real responses,
/// and never calculates a metric the API does not return.
class SellerDashboardView extends StatefulWidget {
  const SellerDashboardView({
    required this.onOpenListings,
    required this.onOpenInquiries,
    required this.onOpenTransactions,
    super.key,
  });

  final VoidCallback onOpenListings;
  final VoidCallback onOpenInquiries;
  final VoidCallback onOpenTransactions;

  @override
  State<SellerDashboardView> createState() => _SellerDashboardViewState();
}

class _SellerDashboardViewState extends State<SellerDashboardView> {
  late final SellerDashboardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SellerDashboardController(
      SellerDashboardScope.readOf(context),
    );
    _controller.loadInitial();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? child) {
        return RefreshIndicator(
          onRefresh: _controller.refresh,
          child: _buildBody(context, _controller.state),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, SellerDashboardState state) {
    final ThemeData theme = Theme.of(context);
    final SellerDashboard? dashboard = state.dashboard;

    if (state.status == SellerDashboardStatus.failed) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.sm,
          AppSpacing.screenGutter,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _DashboardErrorCard(
              message: state.errorMessage ?? 'Could not load your dashboard.',
              onRetry: _controller.retry,
            ),
          ],
        ),
      );
    }

    if (dashboard == null) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.xxl,
          AppSpacing.screenGutter,
          AppSpacing.xl,
        ),
        child: Column(
          children: <Widget>[
            Center(
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
          ],
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.xs,
        AppSpacing.screenGutter,
        AppSpacing.xl,
      ),
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
          if (!dashboard.hasActivity)
            _EmptyDashboardCard(onOpenListings: widget.onOpenListings)
          else ...<Widget>[
            _ListingsCard(
              listings: dashboard.listings,
              onOpenListings: widget.onOpenListings,
            ),
            const SizedBox(height: AppSpacing.md),
            _CountCard(
              title: 'Received Inquiries',
              total: dashboard.inquiries.total,
              unit: _plural(dashboard.inquiries.total, 'inquiry', 'inquiries'),
              detail: dashboard.inquiries.total == 0
                  ? 'No buyer questions yet.'
                  : 'Questions buyers sent about your listings.',
              icon: Icons.mark_email_unread_outlined,
              actionIcon: Icons.arrow_forward,
              actionLabel: 'View inquiries',
              onPressed: widget.onOpenInquiries,
            ),
            const SizedBox(height: AppSpacing.md),
            _CountCard(
              title: 'Transactions',
              total: dashboard.transactions.total,
              unit: _plural(
                dashboard.transactions.total,
                'recorded transaction',
                'recorded transactions',
              ),
              detail: dashboard.transactions.pending == 0
                  ? 'No pending transactions.'
                  : '${dashboard.transactions.pending} '
                        '${_plural(dashboard.transactions.pending, 'pending transaction', 'pending transactions')}.',
              icon: Icons.swap_horiz_outlined,
              actionIcon: Icons.arrow_forward,
              actionLabel: 'View transactions',
              onPressed: widget.onOpenTransactions,
            ),
          ],
        ],
      ),
    );
  }

  static String _plural(int count, String singular, String plural) =>
      count == 1 ? singular : plural;
}

class _ListingsCard extends StatelessWidget {
  const _ListingsCard({required this.listings, required this.onOpenListings});

  final SellerListingSummary listings;
  final VoidCallback onOpenListings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    'My Listings',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${listings.total}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Total listings across every status',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(),
            _StatusRow(label: 'Active', count: listings.active),
            _StatusRow(label: 'Awaiting review', count: listings.pending),
            _StatusRow(label: 'Drafts', count: listings.draft),
            _StatusRow(label: 'Sold', count: listings.sold),
            _StatusRow(label: 'Inactive', count: listings.inactive),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onOpenListings,
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: const Text('Manage listings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.title,
    required this.total,
    required this.unit,
    required this.detail,
    required this.icon,
    required this.actionIcon,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final int total;
  final String unit;
  final String detail;
  final IconData icon;
  final IconData actionIcon;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, size: 20, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        '$total $unit',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(actionIcon, size: 18),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDashboardCard extends StatelessWidget {
  const _EmptyDashboardCard({required this.onOpenListings});

  final VoidCallback onOpenListings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(
                Icons.storefront_outlined,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No seller activity yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Create your first listing to start receiving inquiries and '
              'recording transactions.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onOpenListings,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Manage listings'),
            ),
          ],
        ),
      ),
    );
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
