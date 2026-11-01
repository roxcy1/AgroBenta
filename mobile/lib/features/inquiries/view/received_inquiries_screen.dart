import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../models/received_inquiry.dart';
import '../../../widgets/paged_list_state_views.dart';
import '../../offers/view/make_offer_screen.dart';
import '../state/inquiry_scope.dart';
import '../state/received_inquiries_controller.dart';
import '../state/received_inquiries_state.dart';
import '../widgets/received_inquiries_state_views.dart';
import '../widgets/received_inquiry_card.dart';

/// The authenticated seller's received inquiries.
///
/// The list is always the token's inbox: `GET /seller/inquiries` takes no
/// seller id and its only query parameters are `page` and `per_page`. The
/// inquiry itself stays read-only (its status is an administrator bookmark),
/// but a seller can answer with a structured purchase offer, which is created
/// by `POST /offers` from the inquiry's buyer and listing.
///
/// The controller is owned by this screen and disposed with the route, the same
/// pattern the inquire screen uses. The repository comes from [InquiryScope]
/// above `MaterialApp`, so this pushed route can reach it.
class ReceivedInquiriesScreen extends StatefulWidget {
  const ReceivedInquiriesScreen({super.key});

  @override
  State<ReceivedInquiriesScreen> createState() =>
      _ReceivedInquiriesScreenState();
}

class _ReceivedInquiriesScreenState extends State<ReceivedInquiriesScreen> {
  late final ReceivedInquiriesController _controller;
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _controller = ReceivedInquiriesController(InquiryScope.readOf(context));
    _scroll = ScrollController()..addListener(_onScroll);
    _controller.loadInitial();
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
    if (!_scroll.hasClients) {
      return;
    }
    if (_scroll.position.extentAfter < 400) {
      _controller.loadMore();
    }
  }

  /// Opens the make-offer form. An offer needs both the buyer and the listing:
  /// a null projection means the record cannot be offered against, so the
  /// action is not shown for it in the first place.
  Future<void> _openMakeOffer(ReceivedInquiry inquiry) async {
    final bool? created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => MakeOfferScreen(inquiry: inquiry),
      ),
    );
    if (created == true && mounted) {
      await _controller.refresh();
    }
  }

  /// The offer action is available only when the server sent both sides of the
  /// offer's identity. It never fabricates a buyer or a listing.
  VoidCallback? _makeOfferAction(ReceivedInquiry inquiry) {
    if (inquiry.buyer == null || inquiry.listing == null) {
      return null;
    }
    return () => _openMakeOffer(inquiry);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Received Inquiries')),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Buyer inquiries', style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Questions buyers sent about your listings.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: _controller,
                builder: (BuildContext context, Widget? child) {
                  final ReceivedInquiriesState state = _controller.state;

                  if (state.status == ReceivedInquiriesStatus.loading ||
                      state.status == ReceivedInquiriesStatus.initial) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state.status == ReceivedInquiriesStatus.failed) {
                    return ReceivedInquiriesErrorState(
                      message: state.errorMessage ?? 'Something went wrong.',
                      onRetry: _controller.loadInitial,
                    );
                  }

                  if (state.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _controller.refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: <Widget>[
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.2,
                          ),
                          const ReceivedInquiriesEmptyState(),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _controller.refresh,
                    child: ListView.separated(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenGutter,
                        AppSpacing.sm,
                        AppSpacing.screenGutter,
                        0,
                      ),
                      itemCount: state.inquiries.length + 1,
                      separatorBuilder: (BuildContext context, int index) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (BuildContext context, int index) {
                        if (index >= state.inquiries.length) {
                          return PagedListLoadMoreFooter(
                            isLoading:
                                state.status ==
                                ReceivedInquiriesStatus.loadingMore,
                            hasMore: state.hasMorePages,
                            errorMessage: state.loadMoreErrorMessage,
                            onLoadMore: _controller.loadMore,
                          );
                        }
                        final ReceivedInquiry inquiry = state.inquiries[index];
                        if (index == 0 && state.refreshErrorMessage != null) {
                          return Column(
                            children: <Widget>[
                              PagedListRefreshNotice(
                                message: state.refreshErrorMessage!,
                                onRetry: _controller.refresh,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              ReceivedInquiryCard(
                                inquiry: inquiry,
                                onMakeOffer: _makeOfferAction(inquiry),
                              ),
                            ],
                          );
                        }
                        return ReceivedInquiryCard(
                          inquiry: inquiry,
                          onMakeOffer: _makeOfferAction(inquiry),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
