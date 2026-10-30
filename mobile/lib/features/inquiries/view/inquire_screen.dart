import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/inquiry.dart';
import '../../../models/listing.dart';
import '../../../models/message.dart';
import '../../../widgets/notice_banner.dart';
import '../../../widgets/section_card.dart';
import '../../auth/state/auth_scope.dart';
import '../../messaging/view/chat_screen.dart';
import '../../messaging/view/conversations_screen.dart';
import '../state/inquiry_controller.dart';
import '../state/inquiry_scope.dart';
import '../state/inquiry_state.dart';
import '../widgets/inquiry_listing_card.dart';
import 'inquiry_already_sent_view.dart';
import 'inquiry_sent_view.dart';
import 'inquiry_validators.dart';

/// One selectable message template: the short button label and the exact
/// message it writes into the field.
///
/// Selecting a template only fills the field — it never submits the inquiry and
/// never replaces the buyer's ability to edit the text afterwards (design spec
/// §3.3).
class _MessageTemplate {
  const _MessageTemplate({required this.label, required this.message});

  final String label;
  final String message;
}

/// The four approved starter messages.
const List<_MessageTemplate> _messageTemplates = <_MessageTemplate>[
  _MessageTemplate(
    label: 'Check availability',
    message: 'Hello! Is this livestock still available?',
  ),
  _MessageTemplate(
    label: 'Discuss the price',
    message:
        "Hello! I'm interested in this livestock. Is the price negotiable?",
  ),
  _MessageTemplate(
    label: 'Visit the farm',
    message: 'Hello! Can I visit your farm to inspect this livestock?',
  ),
  _MessageTemplate(
    label: 'Payment and pickup',
    message:
        "Hello! I'm interested in this livestock. Can we discuss payment and "
        'collection arrangements?',
  ),
];

/// The Inquire About Livestock screen — `POST /api/inquiries`.
///
/// Opened from a listing's detail screen with the real [Listing], so the
/// summary card is the actual selected listing and the request carries its
/// real id (design spec §3.2, §5). Nothing on this screen is sample data.
///
/// ## What is collected, and what is sent
///
/// The form collects exactly three things: the required message, a required
/// preferred payment method and a required preferred livestock collection
/// method. All three are in the backend's allow-list (`StoreInquiryRequest`),
/// so nothing the buyer chooses is silently dropped and nothing the backend
/// cannot store is collected. The obsolete subject, purchase-interest,
/// transaction-method, delivery and schedule fields are no longer rendered or
/// sent (design spec §3.3–§3.6).
///
/// ## Two rules the screen exists to keep
///
/// * **The pre-check comes first.** On open the controller asks
///   `GET /inquiries/listing/{listing}` whether this buyer already has an
///   inquiry. If one exists, the already-sent view replaces the form; a failed
///   check still renders the form with a notice, because the backend's
///   duplicate guard is authoritative.
/// * **Success is the server's answer.** The confirmation view is rendered
///   only from [InquiryUiStatus.succeeded], which the controller publishes
///   only from the create response.
/// * **A failed send keeps the input.** Every failure path returns to the form
///   with the controllers untouched, so a network error never costs the buyer
///   the message they typed.
class InquireScreen extends StatefulWidget {
  const InquireScreen({required this.listing, super.key});

  /// The listing being asked about — passed whole, so the id cannot drift
  /// from the summary the buyer is reading.
  final Listing listing;

  @override
  State<InquireScreen> createState() => _InquireScreenState();
}

class _InquireScreenState extends State<InquireScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _message = TextEditingController();

  late final InquiryController _controller;

  InquiryPaymentMethod? _paymentMethod;
  InquiryCollectionMethod? _collectionMethod;
  InquiryCollectionDateOption? _collectionDateOption;
  DateTime? _preferredSchedule;

  /// Client-side preference errors, shown beside their sections after the
  /// first submit attempt. Cleared the moment the buyer chooses an option;
  /// server `422`s are layered on separately via [InquiryState.errorFor].
  String? _paymentError;
  String? _collectionError;
  String? _dateError;

  /// The field errors currently on screen, so a repeat of the same server
  /// error does not re-validate for nothing.
  Map<String, List<String>> _displayedErrors = const <String, List<String>>{};

  @override
  void initState() {
    super.initState();
    // `readOf`, not `of`: a dependency cannot be registered from `initState`,
    // and this screen rebuilds on every keystroke otherwise. The controller is
    // this screen's alone — an inquiry is a one-shot form, not session state —
    // so it is created here and disposed here.
    _controller = InquiryController(InquiryScope.readOf(context));
    // The pre-check runs before the form is offered. It is deliberately not
    // awaited: the first frame shows the checking state, and the controller
    // publishes the result when it arrives.
    _controller.checkExisting(listingId: widget.listing.id);
  }

  @override
  void dispose() {
    _controller.dispose();
    _message.dispose();
    super.dispose();
  }

  /// A `TextFormField` runs its validator when its value changes and when
  /// `validate()` is called — not when the widget rebuilds. A `422` therefore
  /// arrives after the last validation and would never appear on its field
  /// without this.
  ///
  /// `validate()` is deferred to a post-frame callback because calling it
  /// during a build would re-validate while the tree is being assembled.
  void _revealServerFieldErrors(Map<String, List<String>> errors) {
    if (mapEquals(errors, _displayedErrors)) {
      return;
    }
    _displayedErrors = Map<String, List<String>>.of(errors);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _formKey.currentState?.validate();
      }
    });
  }

  Future<void> _submit() async {
    // The button is disabled while submitting; this guard stops the request
    // already in flight from being followed by another one.
    if (_controller.state.isBusy || _controller.state.isCheckingExisting) {
      return;
    }

    // Validate everything in one pass so the buyer sees every missing answer
    // at once, not one field per attempt.
    final String? paymentError = validateInquiryPaymentMethod(_paymentMethod);
    final String? collectionError = validateInquiryCollectionMethod(
      _collectionMethod,
    );
    final String? dateError = validateInquiryCollectionDateOption(
      _collectionDateOption,
    );
    final String? preferredDateError = validateInquiryPreferredDate(
      _collectionDateOption,
      _preferredSchedule,
    );
    final bool formValid = _formKey.currentState?.validate() ?? false;

    setState(() {
      _paymentError = paymentError;
      _collectionError = collectionError;
      _dateError = preferredDateError;
    });

    if (!formValid ||
        paymentError != null ||
        collectionError != null ||
        dateError != null) {
      return;
    }

    final bool sent = await _controller.send(
      listingId: widget.listing.id,
      message: _message.text,
      collectionDateOption: _collectionDateOption!,
      preferredSchedule: _preferredSchedule,
      // The validators above guarantee both are set on this path.
      paymentMethod: _paymentMethod!,
      collectionMethod: _collectionMethod!,
    );
    if (!mounted) {
      return;
    }
    // On success the state publishes [InquiryUiStatus.succeeded] and the
    // builder swaps to the confirmation view. On failure the form is already
    // intact — the controllers are never cleared — and the builder reveals
    // the field errors. Either way there is nothing left to do here.
    debugPrint(
      sent
          ? 'Inquiry sent for listing ${widget.listing.id}.'
          : 'Inquiry send failed for listing ${widget.listing.id}.',
    );
  }

  /// Opens the conversation with the seller of [widget.listing]. When a
  /// counterpart is known (from a confirmed inquiry) the exact chat thread is
  /// opened; otherwise the Messages inbox is shown.
  void _openMessages({ChatUser? counterpart, int? listingId}) {
    final int currentUserId =
        AuthScope.of(context).state.user?.id ?? 0;
    if (counterpart != null && listingId != null) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => ChatScreen(
            counterpart: counterpart,
            currentUserId: currentUserId,
            listingId: listingId,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ConversationsScreen(),
      ),
    );
  }

  /// Back to Browse = the buyer shell underneath this stack. Popping to the
  /// first route returns to the shell's IndexedStack with its selected tab and
  /// scroll position intact — in every path that reaches this screen that tab
  /// is Browse (design spec §4.2).
  void _backToBrowse() {
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  /// Writes [template] into the message field, replacing whatever was there.
  ///
  /// Deliberately does not call [_submit]: a template is a starting point the
  /// buyer can edit or replace, not a send action.
  void _applyTemplate(_MessageTemplate template) {
    setState(() {
      _message.text = template.message;
      _message.selection = TextSelection.collapsed(
        offset: _message.text.length,
      );
    });
    // A template supplies text, so any "please enter a message" error shown
    // by a previous attempt is stale. This is outside a build, so validating
    // directly is safe.
    _formKey.currentState?.validate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // A second, tiny listener: the title must flip the moment the server
        // confirms the inquiry, which happens inside the body's own
        // ListenableBuilder. One listenable, two rebuild scopes — cheaper
        // than lifting the whole scaffold under a single listener.
        title: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final InquiryState state = _controller.state;
            if (state.status == InquiryUiStatus.succeeded) {
              return const Text('Inquiry Sent');
            }
            if (state.existingInquiry != null) {
              return const Text('Inquiry Already Sent');
            }
            return const Text('Inquire About Livestock');
          },
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final InquiryState state = _controller.state;
            final bool isSubmitting = state.isBusy;
            final ThemeData theme = Theme.of(context);

            // Must run on every state change, including one that only carries
            // `validationErrors` — see [_revealServerFieldErrors].
            _revealServerFieldErrors(state.validationErrors);

            // The pre-check owns the first frame. Showing the form first would
            // let a buyer start typing an inquiry they cannot submit.
            if (state.isCheckingExisting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(),
                      SizedBox(height: AppSpacing.sm),
                      Text('Checking your inquiries...'),
                    ],
                  ),
                ),
              );
            }

            // One inquiry per buyer per listing, whatever its status: the
            // already-sent state replaces the form entirely.
            if (state.existingInquiry != null) {
              return InquiryAlreadySentView(
                listing: widget.listing,
                onGoToMessages: () => _openMessages(
                  counterpart: ChatUser(
                    id: widget.listing.seller.id,
                    name: widget.listing.seller.name,
                    avatarUrl: null,
                  ),
                  listingId: widget.listing.id,
                ),
                onBackToBrowse: _backToBrowse,
              );
            }

            if (state.status == InquiryUiStatus.succeeded) {
              return InquirySentView(
                listing: widget.listing,
                // Succeeded is published only from the create response, so
                // the record is present; the non-null assertion asserts that
                // controller invariant, not a hope.
                inquiry: state.inquiry!,
                onGoToMessages: () => _openMessages(
                  counterpart: ChatUser(
                    id: widget.listing.seller.id,
                    name: widget.listing.seller.name,
                    avatarUrl: null,
                  ),
                  listingId: widget.listing.id,
                ),
                onBackToBrowse: _backToBrowse,
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (state.existingCheckError != null) ...<Widget>[
                          // The check failed, so the form stays usable: the
                          // backend's duplicate guard is the authority. The
                          // notice explains why the form appeared without a
                          // confirmation that none exists.
                          NoticeBanner(
                            accent: AppColors.warning,
                            icon: Icons.info_outline,
                            message: state.existingCheckError!,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        if (state.errorMessage != null) ...<Widget>[
                          NoticeBanner(
                            accent: AppColors.error,
                            icon: Icons.error_outline,
                            message: state.errorMessage!,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        InquiryListingCard(listing: widget.listing),
                        const SizedBox(height: AppSpacing.md),
                        ..._paymentMethodSection(isSubmitting),
                        const SizedBox(height: AppSpacing.md),
                        ..._collectionMethodSection(isSubmitting),
                        const SizedBox(height: AppSpacing.md),
                        ..._collectionDateSection(isSubmitting),
                        const SizedBox(height: AppSpacing.md),
                        ..._messageSection(isSubmitting),
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton(
                                // Cancel never submits. There is no unsaved-
                                // changes confirmation pattern in this app yet,
                                // so it navigates back exactly as the back
                                // arrow does.
                                onPressed: isSubmitting
                                    ? null
                                    : () => Navigator.of(context).maybePop(),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: FilledButton(
                                // Disabled while submitting, and the controller
                                // also refuses a second call in flight: the
                                // button stops the tap, the guard stops the
                                // request already on its way.
                                onPressed: isSubmitting ? null : _submit,
                                child: isSubmitting
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Send Inquiry'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'The seller will reply through AgroBenta messages.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _messageSection(bool isSubmitting) {
    final ThemeData theme = Theme.of(context);
    final int length = _message.text.length;
    final bool overLimit = length > kInquiryMessageMax;

    return <Widget>[
      SectionCard(
        title: 'Additional Message',
        children: <Widget>[
          Text(
            'Tell the seller what you would like to know.',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _message,
            enabled: !isSubmitting,
            minLines: 4,
            maxLines: 6,
            maxLength: kInquiryMessageMax,
            textInputAction: TextInputAction.newline,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Message *',
              alignLabelWithHint: true,
              hintText: 'Type your inquiry here...',
              helperText:
                  'Ask about availability, additional photos, or the '
                  'asking price.',
              // The default counter is hidden and replaced by the exact
              // `currentLength/500` form the design spec asks for, below.
              counterText: '',
              errorMaxLines: 2,
            ),
            validator: (String? value) =>
                validateInquiryMessage(value) ??
                _controller.state.errorFor('message'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$length/$kInquiryMessageMax',
              style: theme.textTheme.bodySmall?.copyWith(
                color: overLimit
                    ? theme.colorScheme.error
                    : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Message templates', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final _MessageTemplate template in _messageTemplates)
                OutlinedButton(
                  onPressed: isSubmitting
                      ? null
                      : () => _applyTemplate(template),
                  child: Text(template.label),
                ),
            ],
          ),
        ],
      ),
    ];
  }

  List<Widget> _paymentMethodSection(bool isSubmitting) {
    final ThemeData theme = Theme.of(context);
    final String? error =
        _paymentError ?? _controller.state.errorFor('payment_method');

    return <Widget>[
      SectionCard(
        title: 'Preferred Payment Method *',
        children: <Widget>[
          Text(
            'How would you prefer to pay the seller?',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _PreferenceCard(
                    selected: _paymentMethod == InquiryPaymentMethod.cash,
                    icon: Icons.money_outlined,
                    title: 'Cash',
                    subtitle: 'Pay with cash.',
                    enabled: !isSubmitting,
                    onTap: () => setState(() {
                      _paymentMethod = InquiryPaymentMethod.cash;
                      _paymentError = null;
                    }),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _PreferenceCard(
                    selected: _paymentMethod == InquiryPaymentMethod.gcash,
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'GCash',
                    subtitle: 'Pay with GCash.',
                    enabled: !isSubmitting,
                    onTap: () => setState(() {
                      _paymentMethod = InquiryPaymentMethod.gcash;
                      _paymentError = null;
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _PreferenceCard(
                    selected: _paymentMethod == InquiryPaymentMethod.maya,
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Maya',
                    subtitle: 'Pay with Maya.',
                    enabled: !isSubmitting,
                    onTap: () => setState(() {
                      _paymentMethod = InquiryPaymentMethod.maya;
                      _paymentError = null;
                    }),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _PreferenceCard(
                    selected: _paymentMethod == InquiryPaymentMethod.other,
                    icon: Icons.help_outline,
                    title: 'Other / Discuss with seller',
                    subtitle: 'Agree payment with the seller.',
                    enabled: !isSubmitting,
                    onTap: () => setState(() {
                      _paymentMethod = InquiryPaymentMethod.other;
                      _paymentError = null;
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (error != null)
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _collectionMethodSection(bool isSubmitting) {
    final ThemeData theme = Theme.of(context);
    final String? error =
        _collectionError ?? _controller.state.errorFor('collection_method');

    return <Widget>[
      SectionCard(
        title: 'Preferred Livestock Collection *',
        children: <Widget>[
          Text(
            'How do you plan to receive the livestock?',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _PreferenceCard(
                    selected:
                        _collectionMethod == InquiryCollectionMethod.farmPickup,
                    icon: Icons.location_on_outlined,
                    title: 'Farm Pickup',
                    subtitle: 'Pick up from the seller\'s farm.',
                    enabled: !isSubmitting,
                    onTap: () => setState(() {
                      _collectionMethod = InquiryCollectionMethod.farmPickup;
                      _collectionError = null;
                    }),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _PreferenceCard(
                    selected:
                        _collectionMethod ==
                        InquiryCollectionMethod.buyerArrangedTransportation,
                    icon: Icons.directions_car_outlined,
                    title: 'Arrange Transport',
                    subtitle: 'Arrange my own livestock transportation.',
                    enabled: !isSubmitting,
                    onTap: () => setState(() {
                      _collectionMethod =
                          InquiryCollectionMethod.buyerArrangedTransportation;
                      _collectionError = null;
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _PreferenceCard(
                    selected:
                        _collectionMethod ==
                        InquiryCollectionMethod.discussWithSeller,
                    icon: Icons.chat_bubble_outline,
                    title: 'Discuss',
                    subtitle: 'Discuss arrangements with the seller.',
                    enabled: !isSubmitting,
                    onTap: () => setState(() {
                      _collectionMethod =
                          InquiryCollectionMethod.discussWithSeller;
                      _collectionError = null;
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (error != null)
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _collectionDateSection(bool isSubmitting) {
    final ThemeData theme = Theme.of(context);
    final String? error = _dateError ?? _controller.state.errorFor('preferred_schedule');
    final String? optionError = _controller.state.errorFor('collection_date_option');
    final String? selectedDate = _preferredSchedule == null
        ? null
        : '${_preferredSchedule!.year}-${_preferredSchedule!.month.toString().padLeft(2, '0')}-${_preferredSchedule!.day.toString().padLeft(2, '0')}';

    return <Widget>[
      SectionCard(
        title: 'Preferred Collection Date *',
        children: <Widget>[
          Text(
            'When do you hope to collect the livestock?',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._dateOptionCards(isSubmitting, theme),
          const SizedBox(height: AppSpacing.sm),
          if (_collectionDateOption == InquiryCollectionDateOption.nextFewDays) ...<Widget>[
            ..._nextFewDaysDateChips(isSubmitting),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (_collectionDateOption == InquiryCollectionDateOption.specificDate) ...<Widget>[
            ListTile(
              leading: const Icon(Icons.calendar_today, size: 20),
              title: const Text('Specific date'),
              subtitle: Text(
                selectedDate == null
                    ? 'Pick a date'
                    : 'Selected: $selectedDate',
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: !isSubmitting,
              onTap: isSubmitting ? null : _pickDate,
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (optionError != null)
            Text(
              optionError,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          if (error != null)
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _dateOptionCards(bool isSubmitting, ThemeData theme) {
    return <Widget>[
      _PreferenceCard(
        selected: _collectionDateOption == InquiryCollectionDateOption.specificDate,
        icon: Icons.calendar_today,
        title: 'Specific date',
        subtitle: 'Choose an exact date.',
        enabled: !isSubmitting,
        onTap: () => setState(() {
          _collectionDateOption = InquiryCollectionDateOption.specificDate;
          _dateError = null;
        }),
      ),
      const SizedBox(width: AppSpacing.sm),
      _PreferenceCard(
        selected: _collectionDateOption == InquiryCollectionDateOption.nextFewDays,
        icon: Icons.event_busy,
        title: 'Next few days',
        subtitle: 'Within the next few days.',
        enabled: !isSubmitting,
        onTap: () => setState(() {
          _collectionDateOption = InquiryCollectionDateOption.nextFewDays;
          _dateError = null;
        }),
      ),
      const SizedBox(width: AppSpacing.sm),
      _PreferenceCard(
        selected: _collectionDateOption == InquiryCollectionDateOption.thisWeek,
        icon: Icons.today,
        title: 'This week',
        subtitle: 'Within this week.',
        enabled: !isSubmitting,
        onTap: () => setState(() {
          _collectionDateOption = InquiryCollectionDateOption.thisWeek;
          _dateError = null;
        }),
      ),
    ];
  }

  Future<void> _pickDate() async {
    final DateTime today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: DateTime(today.year + 1),
    );
    if (picked != null && mounted) {
      setState(() {
        _preferredSchedule = picked;
        _dateError = null;
      });
    }
  }

  List<Widget> _nextFewDaysDateChips(bool isSubmitting) {
    final ThemeData theme = Theme.of(context);
    final DateTime today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final List<DateTime> options = <DateTime>[
      today.add(const Duration(days: 1)),
      today.add(const Duration(days: 2)),
      today.add(const Duration(days: 3)),
    ];

    return <Widget>[
      Text(
        'Choose a date',
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          for (int index = 0; index < options.length; index += 1)
            _nextFewDaysChip(options[index], index, isSubmitting),
        ],
      ),
    ];
  }

  Widget _nextFewDaysChip(DateTime date, int index, bool isSubmitting) {
    final bool selected = _preferredSchedule != null &&
        _preferredSchedule!.year == date.year &&
        _preferredSchedule!.month == date.month &&
        _preferredSchedule!.day == date.day;
    final String label;
    switch (index) {
      case 0:
        label = 'Tomorrow';
        break;
      case 1:
        label = 'Day 2';
        break;
      default:
        label = 'Day 3';
        break;
    }
    return _PreferenceCard(
      selected: selected,
      icon: Icons.event,
      title: label,
      subtitle: AppFormatters.formatDate(date),
      enabled: !isSubmitting,
      onTap: () => setState(() {
        _preferredSchedule = date;
        _dateError = null;
      }),
    );
  }
}

/// One selectable preference card, reused by the payment and collection
/// method sections. The selected state is carried three ways — border, tint,
/// and [Semantics.selected] — so it does not depend on colour alone.
class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BorderRadius radius = BorderRadius.circular(AppRadius.md);

    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $subtitle',
      child: Material(
        color: selected ? AppColors.primarySurface : AppColors.surface,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: <Widget>[
                Icon(
                  icon,
                  size: 24,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: selected ? AppColors.primary : AppColors.text,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
