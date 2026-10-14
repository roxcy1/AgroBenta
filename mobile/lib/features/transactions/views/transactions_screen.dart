import 'package:flutter/material.dart';

import '../../../models/transaction.dart';
import '../../../repositories/transaction_repository.dart';
import '../state/transaction_scope.dart';
import '../state/transactions_controller.dart';
import 'transaction_tab.dart';

/// The caller's transactions, tabbed by lifecycle state.
///
/// Three tabs — `[Ongoing] [Completed] [Cancelled]` — each an independent
/// filtered query (`pending`, `completed`, `cancelled`). Ongoing is the only
/// mutable state; the other two are terminal and immutable.
///
/// The Completed tab is honestly empty for a long time: no path in the app
/// can reach `completed` today (OQ-15), and that is correct rather than a
/// bug to work around by faking a completion path.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final List<TransactionsController> _controllers;

  static const List<TransactionStatus> tabStatuses = <TransactionStatus>[
    TransactionStatus.pending,
    TransactionStatus.completed,
    TransactionStatus.cancelled,
  ];

  static const List<String> _tabLabels = <String>[
    'Ongoing',
    'Completed',
    'Cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: tabStatuses.length, vsync: this);
    // Read once: the repository identity never changes for the session.
    final TransactionRepository repository = TransactionScope.readOf(context);
    _controllers = <TransactionsController>[
      for (final TransactionStatus status in tabStatuses)
        TransactionsController(repository, status),
    ];
    _controllers.first.loadInitial();
  }

  @override
  void dispose() {
    for (final TransactionsController controller in _controllers) {
      controller.dispose();
    }
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        bottom: TabBar(
          controller: _tabs,
          onTap: (int index) => _controllers[index].loadInitial(),
          tabs: <Widget>[
            for (final String label in _tabLabels) Tab(text: label),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabs,
          children: <Widget>[
            for (int i = 0; i < tabStatuses.length; i++)
              TransactionsTab(
                controller: _controllers[i],
                status: tabStatuses[i],
              ),
          ],
        ),
      ),
    );
  }
}
