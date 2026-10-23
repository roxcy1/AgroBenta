import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../models/transaction.dart';
import '../../../repositories/transaction_repository.dart';
import '../state/transaction_scope.dart';
import '../state/transactions_controller.dart';
import '../state/transactions_filter.dart';
import '../state/transactions_state.dart';
import '../widgets/transaction_filter_bar.dart';
import 'transaction_tab.dart';

/// The authenticated buyer's purchases, filtered by lifecycle state.
///
/// Every query sends `role=buyer`: this screen is **My Purchases**, not a
/// combined ledger, so a seller's sale must never appear here. The server
/// derives the caller from the token; no user id is sent.
///
/// "All" is the default and sends no `status`; the three working filters send
/// the three statuses the backend persists. The design's extra "Pending" chip
/// is not shown — it is the same server state as "Ongoing" — see
/// [TransactionsFilter].
///
/// The Completed filter is honestly empty for a long time: no path in the app
/// can reach `completed` today (the backend's complete endpoint answers 501,
/// OQ-15), and that is correct rather than a bug to work around by faking a
/// completion path.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late final Map<TransactionsFilter, TransactionsController> _controllers;
  TransactionsFilter _filter = TransactionsFilter.all;

  @override
  void initState() {
    super.initState();
    // Read once: the repository identity never changes for the session.
    final TransactionRepository repository = TransactionScope.readOf(context);
    _controllers = <TransactionsFilter, TransactionsController>{
      for (final TransactionsFilter filter in TransactionsFilter.values)
        filter: TransactionsController(
          repository,
          filter.status,
          role: TransactionRole.buyer,
        ),
    };
    _controllers[TransactionsFilter.all]!.loadInitial();
  }

  @override
  void dispose() {
    for (final TransactionsController controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _select(TransactionsFilter filter) {
    if (filter == _filter) {
      return;
    }
    setState(() => _filter = filter);

    final TransactionsController controller = _controllers[filter]!;
    // Load lazily, once. Re-selecting a filter keeps what it already loaded.
    if (controller.state.status == TransactionsStatus.initial) {
      controller.loadInitial();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                AppSpacing.md,
                AppSpacing.screenGutter,
                AppSpacing.xs,
              ),
              child: Text('My Purchases', style: theme.textTheme.titleLarge),
            ),
            TransactionFilterBar(selected: _filter, onSelected: _select),
            const SizedBox(height: AppSpacing.xs),
            Expanded(
              child: TransactionsTab(
                // One live list at a time. The controllers keep the loaded
                // pages, so switching back shows them immediately.
                key: ValueKey<TransactionsFilter>(_filter),
                controller: _controllers[_filter]!,
                filter: _filter,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
