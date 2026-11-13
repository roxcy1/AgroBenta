import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

const List<String> _helpCategories = <String>[
  'Account & Profile',
  'Buying Livestock',
  'Selling Livestock',
  'Transactions',
  'Safety & Security',
];

// Account and address facts: docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md §2.8
// and §3.3, plus the implemented Profile and password screens.
const List<_HelpArticle> _helpArticles = <_HelpArticle>[
  _HelpArticle(
    category: 'Account & Profile',
    question: 'How do I update my personal information?',
    answer:
        'Open Profile, choose Personal Information, edit the available fields, '
        'and save your changes.',
  ),
  _HelpArticle(
    category: 'Account & Profile',
    question: 'How do I update my address?',
    answer:
        'Open Address from Profile. Choose a supported barangay in Trinidad, '
        'Bohol, and optionally enter a Street or Purok before saving. Profile '
        'addresses are optional.',
  ),
  _HelpArticle(
    category: 'Account & Profile',
    question: 'How do I change my password?',
    answer:
        'Open Change Password from Profile and follow the on-screen prompts.',
  ),
  // Buying: functional documentation §4.4 and §8.1–8.2, plus the implemented
  // marketplace, inquiry, messaging and offer flows.
  _HelpArticle(
    category: 'Buying Livestock',
    question: 'How do I browse livestock?',
    answer:
        'Open Browse to search and filter livestock. Only active listings are '
        'shown to buyers.',
  ),
  _HelpArticle(
    category: 'Buying Livestock',
    question: 'How do I contact a seller?',
    answer:
        'Open a listing and choose Ask Seller to start or open your conversation '
        'in Messages. Asking a question does not create an inquiry or reserve '
        'the listing.',
  ),
  _HelpArticle(
    category: 'Buying Livestock',
    question: 'How do I send an inquiry?',
    answer:
        'Choose I’m Interested on a listing and submit the inquiry with your '
        'payment and collection preferences. The message and preferred date are '
        'optional. An inquiry does not reserve livestock or create a transaction.',
  ),
  _HelpArticle(
    category: 'Buying Livestock',
    question: 'How do I accept a seller’s offer?',
    answer:
        'Open the conversation in Messages and review the offer. Accepting it '
        'creates a pending transaction and reserves the agreed quantity. You can '
        'also decline an offer from the conversation.',
  ),
  // Selling: functional documentation §3 and §4.2–4.4. Inquiry replies use
  // Messages (§8.2); offer actions follow the flow in §6.4.
  _HelpArticle(
    category: 'Selling Livestock',
    question: 'How do I become a seller?',
    answer:
        'Submit Seller Verification from Profile. Seller features become '
        'available only after the administrator approves your application; '
        'submitting an application does not grant seller access.',
  ),
  _HelpArticle(
    category: 'Selling Livestock',
    question: 'How do I create a listing?',
    answer:
        'After seller approval, switch to Seller Mode and create a listing. '
        'New listings are saved as drafts. Submit a complete draft for review; '
        'it becomes visible to buyers only when approved and active.',
  ),
  _HelpArticle(
    category: 'Selling Livestock',
    question: 'How do I manage my listings?',
    answer:
        'In Seller Mode, open My Listings to view and manage your own listings. '
        'Available actions depend on the listing’s current status.',
  ),
  _HelpArticle(
    category: 'Selling Livestock',
    question: 'How do I respond to a buyer inquiry?',
    answer:
        'Open the buyer’s conversation in Messages to reply. When the inquiry is '
        'eligible, use Make an Offer to send a structured offer.',
  ),
  // Transactions: functional documentation §6.3–6.5 and the implemented
  // fulfillment and receipt screens.
  _HelpArticle(
    category: 'Transactions',
    question: 'Who arranges pickup or delivery?',
    answer:
        'The buyer and seller arrange collection and any transportation '
        'themselves. AgroBenta records the agreed method and seller-reported '
        'fulfillment steps; it does not provide transportation or process payment.',
  ),
  _HelpArticle(
    category: 'Transactions',
    question: 'What do transaction statuses mean?',
    answer:
        'Ongoing represents a pending transaction. Completed and Cancelled are '
        'terminal statuses. Pickup or delivery progress is shown separately as '
        'the seller updates fulfillment.',
  ),
  _HelpArticle(
    category: 'Transactions',
    question: 'How do I confirm receipt?',
    answer:
        'After the seller records that livestock was picked up or delivered, '
        'the buyer can choose Confirm Received. This completes the transaction. '
        'The resulting receipt records the sale; it is not proof of payment.',
  ),
  _HelpArticle(
    category: 'Transactions',
    question: 'When can a transaction be cancelled?',
    answer:
        'Either party can cancel a pending transaction before livestock '
        'handover or seller dispatch. Cancellation is no longer available after '
        'handover or dispatch.',
  ),
  // Security: functional documentation §2.6 and §10, plus current account UI.
  _HelpArticle(
    category: 'Safety & Security',
    question: 'How can I protect my account?',
    answer:
        'Use Change Password from Profile to update your password. If you cannot '
        'sign in, Forgot Password is available from the sign-in screen; reset '
        'email delivery depends on service configuration.',
  ),
  _HelpArticle(
    category: 'Safety & Security',
    question: 'What does seller verification mean?',
    answer:
        'Seller access is granted only after the administrator approves the '
        'seller’s verification application. Submitting an application does not '
        'grant seller access.',
  ),
  _HelpArticle(
    category: 'Safety & Security',
    question: 'What should I do if something seems suspicious?',
    answer:
        'A dedicated suspicious-activity report action and direct support '
        'contact are not currently configured in the app.',
  ),
];

class _HelpArticle {
  const _HelpArticle({
    required this.category,
    required this.question,
    required this.answer,
  });

  final String category;
  final String question;
  final String answer;
}

/// Bundled, searchable help content for the authenticated mobile app.
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_HelpArticle> get _visibleArticles {
    final String query = _query.trim().toLowerCase();
    return _helpArticles
        .where((_HelpArticle article) {
          if (_selectedCategory != null &&
              article.category != _selectedCategory) {
            return false;
          }
          if (query.isEmpty) return true;
          return article.category.toLowerCase().contains(query) ||
              article.question.toLowerCase().contains(query) ||
              article.answer.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<_HelpArticle> articles = _visibleArticles;

    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          children: <Widget>[
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'How can we help you today?',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      key: const ValueKey<String>('help-search-field'),
                      controller: _searchController,
                      onChanged: (String value) =>
                          setState(() => _query = value),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search help topics...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text('Categories', style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: <Widget>[
                        ChoiceChip(
                          label: const Text('All topics'),
                          selected: _selectedCategory == null,
                          onSelected: (_) =>
                              setState(() => _selectedCategory = null),
                        ),
                        for (final String category in _helpCategories)
                          ChoiceChip(
                            label: Text(category),
                            selected: _selectedCategory == category,
                            onSelected: (_) => setState(
                              () => _selectedCategory =
                                  _selectedCategory == category
                                  ? null
                                  : category,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (articles.isEmpty)
                      _NoHelpResults(query: _query)
                    else
                      for (final _HelpArticle article in articles) ...<Widget>[
                        Card(
                          margin: EdgeInsets.zero,
                          child: ExpansionTile(
                            key: PageStorageKey<String>(article.question),
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              0,
                              AppSpacing.md,
                              AppSpacing.md,
                            ),
                            title: Text(
                              article.question,
                              style: theme.textTheme.titleSmall,
                            ),
                            subtitle: Text(
                              article.category,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            children: <Widget>[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  article.answer,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                    const SizedBox(height: AppSpacing.sm),
                    Card(
                      color: AppColors.primarySurface,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Contact Support',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              'Direct support contact is not configured yet.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoHelpResults extends StatelessWidget {
  const _NoHelpResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: <Widget>[
          Icon(Icons.search_off, color: AppColors.textSecondary, size: 28),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'No help topics found',
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            query.trim().isEmpty
                ? 'Choose another category to see its topics.'
                : 'Try a different search or category.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
