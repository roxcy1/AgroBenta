import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../models/transaction.dart';
import '../state/transactions_controller.dart';
import '../state/transactions_filter.dart';
import '../state/transactions_state.dart';
import '../widgets/transaction_card.dart';
import '../widgets/transactions_state_views.dart';
import 'transaction_detail_screen.dart';

/// One filter's list, driven entirely by its controller's state.
///
/// The controller outlives the widget, so switching filters and back shows the
/// pages already loaded. The list makes no request of its own: it forwards
/// intent to the controller and renders whatever state comes back.
class TransactionsTab extends StatefulWidget {
  const TransactionsTab({
    required this.controller,
    required this.filter,
    required this.role,
    super.key,
  });

  final TransactionsController controller;
  final TransactionsFilter filter;
  final TransactionRole role;

  @override
  State<TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<TransactionsTab> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    if (_scroll.position.extentAfter < 400) {
      widget.controller.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final TransactionsState state = widget.controller.state;

        if (state.status == TransactionsStatus.loading ||
            state.status == TransactionsStatus.initial) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.status == TransactionsStatus.failed) {
          return TransactionsErrorState(
            message: state.errorMessage ?? 'Something went wrong.',
            onRetry: widget.controller.loadInitial,
          );
        }

        if (state.isEmpty) {
          return RefreshIndicator(
            onRefresh: widget.controller.refresh,
            child: ListView(
              // Pull-to-refresh must work even when the list is empty or
              // shorter than the viewport — the situation where refreshing
              // matters most.
              physics: const AlwaysScrollableScrollPhysics(),
              children: <Widget>[
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
                TransactionsEmptyState(
                  filter: widget.filter,
                  role: widget.role,
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: widget.controller.refresh,
          child: ListView.separated(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              0,
            ),
            itemCount: state.transactions.length + 1,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (BuildContext context, int index) {
              if (index >= state.transactions.length) {
                return TransactionsLoadMoreFooter(
                  isLoading: state.status == TransactionsStatus.loadingMore,
                  hasMore: state.hasMorePages,
                  errorMessage: state.loadMoreErrorMessage,
                  onLoadMore: widget.controller.loadMore,
                );
              }
              final Transaction transaction = state.transactions[index];
              if (index == 0 && state.refreshErrorMessage != null) {
                return Column(
                  children: <Widget>[
                    TransactionsRefreshNotice(
                      message: state.refreshErrorMessage!,
                      onRetry: widget.controller.refresh,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _card(transaction),
                  ],
                );
              }
              return _card(transaction);
            },
          ),
        );
      },
    );
  }

  Widget _card(Transaction transaction) {
    return TransactionCard(
      transaction: transaction,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              TransactionDetailScreen(transactionId: transaction.id),
        ),
      ),
    );
  }
}
