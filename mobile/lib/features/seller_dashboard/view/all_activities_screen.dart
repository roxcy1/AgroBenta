import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/seller_activity.dart';
import '../../../widgets/paged_list_state_views.dart';
import '../state/seller_activities_controller.dart';
import '../state/seller_activity_scope.dart';
import '../widgets/seller_activity_tile.dart';

/// The seller's full activity history, with category and date filters.
///
/// State (category, date range, pages) belongs to [SellerActivitiesController],
/// so load-more and refresh keep the active filters. Navigation reuses the same
/// safe destinations as Seller Home's latest-five feed.
class AllActivitiesScreen extends StatefulWidget {
  const AllActivitiesScreen({
<<<<<<< Updated upstream
=======
    required this.onOpenMessages,
>>>>>>> Stashed changes
    required this.onOpenListings,
    required this.onOpenTransactions,
    this.onOpenOffer,
    this.onOpenTransaction,
    super.key,
  });

<<<<<<< Updated upstream
=======
  final VoidCallback onOpenMessages;
>>>>>>> Stashed changes
  final VoidCallback onOpenListings;
  final VoidCallback onOpenTransactions;
  final void Function(int buyerId, int? transactionId)? onOpenOffer;
  final ValueChanged<int>? onOpenTransaction;

  @override
  State<AllActivitiesScreen> createState() => _AllActivitiesScreenState();
}

class _AllActivitiesScreenState extends State<AllActivitiesScreen> {
  static const List<(String?, String)> _categories = <(String?, String)>[
    (null, 'All'),
    ('listings', 'Listings'),
    ('offers', 'Offers'),
    ('transactions', 'Transactions'),
  ];

  late final SellerActivitiesController _controller;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = SellerActivitiesController(
      SellerActivityScope.readOf(context),
    )..loadInitial();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 320 &&
        _controller.state.hasMorePages) {
      _controller.loadMore();
    }
  }

  Future<void> _selectCategory(String? category) => _controller.setCategory(category);

  Future<void> _selectAllTime() => _controller.setDateRange(null, null);

  Future<void> _selectToday() {
    final DateTime now = DateTime.now();
    final DateTime day = DateTime(now.year, now.month, now.day);
    return _controller.setDateRange(day, day);
  }

  Future<void> _selectLastDays(int days) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return _controller.setDateRange(
      today.subtract(Duration(days: days - 1)),
      today,
    );
  }

  Future<void> _selectCustomRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _controller.state.from != null &&
              _controller.state.to != null
          ? DateTimeRange(
              start: _controller.state.from!,
              end: _controller.state.to!,
            )
          : null,
    );
    if (range == null || !mounted) {
      return;
    }
    await _controller.setDateRange(range.start, range.end);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All Activities')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListenableBuilder(
              listenable: _controller,
              builder: (BuildContext context, Widget? child) {
                final SellerActivitiesState state = _controller.state;

                return Column(
                  children: <Widget>[
                    _CategoryChips(
                      selected: state.category,
                      onSelected: _selectCategory,
                    ),
                    _DateChips(state: state, actions: _DateActions(
                      allTime: _selectAllTime,
                      today: _selectToday,
                      last7: () => _selectLastDays(7),
                      last30: () => _selectLastDays(30),
                      custom: _selectCustomRange,
                      clear: _controller.clearFilters,
                      hasFilters: state.hasActiveFilters,
                    )),
                    const Divider(height: 1),
                    Expanded(child: _body(state)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(SellerActivitiesState state) {
    if (state.isInitialLoad) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.status == SellerActivitiesStatus.failed) {
      return _MessageState(
        message: state.errorMessage ?? 'Could not load activities.',
        actionLabel: 'Try again',
        onAction: _controller.retry,
      );
    }

    if (state.status == SellerActivitiesStatus.empty) {
      return _MessageState(
        message: state.hasActiveFilters
            ? 'No activities match these filters.'
            : 'No activity yet.',
        actionLabel: state.hasActiveFilters ? 'Clear filters' : null,
        onAction: _controller.clearFilters,
      );
    }

    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.sm,
          AppSpacing.screenGutter,
          AppSpacing.lg,
        ),
        itemCount: state.activities.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0 && state.refreshErrorMessage != null) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: PagedListRefreshNotice(
                message: state.refreshErrorMessage!,
                onRetry: _controller.refresh,
              ),
            );
          }

          final int offset = state.refreshErrorMessage != null ? 1 : 0;
          final int activityIndex = index - offset;

          if (activityIndex >= state.activities.length) {
            return PagedListLoadMoreFooter(
              isLoading:
                  state.status == SellerActivitiesStatus.loadingMore,
              hasMore: state.hasMorePages,
              errorMessage: state.loadMoreErrorMessage,
              onLoadMore: _controller.loadMore,
            );
          }

          final SellerActivity activity = state.activities[activityIndex];
          return SellerActivityTile(
            activity: activity,
            onTap: _actionFor(activity),
          );
        },
      ),
    );
  }

  VoidCallback? _actionFor(SellerActivity activity) {
    final String action = activity.action;

    if (action.startsWith('inquiry')) {
<<<<<<< Updated upstream
      // Inquiries are delivered as messages now (§8.2): there is no seller
      // inbox to open, so activity rows have nothing to navigate to here.
      return null;
=======
      return widget.onOpenMessages;
>>>>>>> Stashed changes
    }
    if (action.startsWith('offer')) {
      final int? buyerId = activity.buyerId;
      if (buyerId != null && widget.onOpenOffer != null) {
        return () => widget.onOpenOffer!(buyerId, activity.transactionId);
      }
<<<<<<< Updated upstream
      return null;
=======
      return widget.onOpenMessages;
>>>>>>> Stashed changes
    }
    if (action.startsWith('listing')) {
      return widget.onOpenListings;
    }
    if (action.startsWith('transaction')) {
      final int? id = activity.transactionId ?? activity.targetId;
      if (id != null && widget.onOpenTransaction != null) {
        return () => widget.onOpenTransaction!(id);
      }
      return widget.onOpenTransactions;
    }
    return null;
  }
}

class _DateActions {
  const _DateActions({
    required this.allTime,
    required this.today,
    required this.last7,
    required this.last30,
    required this.custom,
    required this.clear,
    required this.hasFilters,
  });

  final VoidCallback allTime;
  final VoidCallback today;
  final VoidCallback last7;
  final VoidCallback last30;
  final VoidCallback custom;
  final VoidCallback clear;
  final bool hasFilters;
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        itemCount: _AllActivitiesScreenState._categories.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: AppSpacing.xs),
        itemBuilder: (BuildContext context, int index) {
          final (String? value, String label) =
              _AllActivitiesScreenState._categories[index];
          return Center(
            child: ChoiceChip(
              key: ValueKey<String>('activity-category-${value ?? 'all'}'),
              label: Text(label),
              selected: value == selected,
              showCheckmark: false,
              onSelected: (_) => onSelected(value),
            ),
          );
        },
      ),
    );
  }
}

class _DateChips extends StatelessWidget {
  const _DateChips({required this.state, required this.actions});

  final SellerActivitiesState state;
  final _DateActions actions;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final bool isAllTime = state.from == null && state.to == null;
    final bool isToday = _isSameDay(state.from, today) &&
        _isSameDay(state.to, today);
    final bool isLast7 = _isSameDay(
          state.from,
          today.subtract(const Duration(days: 6)),
        ) &&
        _isSameDay(state.to, today);
    final bool isLast30 = _isSameDay(
          state.from,
          today.subtract(const Duration(days: 29)),
        ) &&
        _isSameDay(state.to, today);
    final bool isCustom = !isAllTime && !isToday && !isLast7 && !isLast30;

    return SizedBox(
      height: 48,
      child: Row(
        children: <Widget>[
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenGutter,
              ),
              children: <Widget>[
                _chip('All Time', isAllTime, actions.allTime, key: 'all-time'),
                const SizedBox(width: AppSpacing.xs),
                _chip('Today', isToday, actions.today, key: 'today'),
                const SizedBox(width: AppSpacing.xs),
                _chip('Last 7 Days', isLast7, actions.last7, key: 'last-7'),
                const SizedBox(width: AppSpacing.xs),
                _chip('Last 30 Days', isLast30, actions.last30, key: 'last-30'),
                const SizedBox(width: AppSpacing.xs),
                _chip('Custom Range', isCustom, actions.custom, key: 'custom'),
              ],
            ),
          ),
          if (actions.hasFilters)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: TextButton(
                onPressed: actions.clear,
                child: const Text('Clear'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap,
      {required String key}) {
    return Center(
      child: ChoiceChip(
        key: ValueKey<String>('activity-date-$key'),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      ),
    );
  }

  static bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) {
      return false;
    }
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.history_toggle_off,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
