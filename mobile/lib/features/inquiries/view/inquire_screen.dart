import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/inquiry.dart';
import '../../../models/listing.dart';
import '../../../widgets/notice_banner.dart';
import '../../../widgets/section_card.dart';
import '../state/inquiry_controller.dart';
import '../state/inquiry_scope.dart';
import '../state/inquiry_state.dart';
import '../widgets/inquiry_listing_card.dart';
import 'inquiry_sent_view.dart';
import 'inquiry_validators.dart';

/// The Inquire About Livestock screen — `POST /api/inquiries`.
///
/// Opened from a listing's detail screen with the real [Listing], so the
/// summary card is the actual selected listing and the request carries its
/// real id (design spec §3.2, §5). Nothing on this screen is sample data.
///
/// ## What is collected, and what is sent
///
/// The form gathers the full set of preferences the `inquiries` schema stores
/// ([InquiryEndpoints]-side allow-list in `InquiryService`): message and
/// purchase interest (both required here), plus the optional subject,
/// transaction method, delivery details, contact method and preferred
/// schedule. Nothing the backend cannot store is collected, and nothing the
/// backend stores is silently dropped (design spec §3.6).
///
/// Two rules the screen exists to keep:
///
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

  /// Starts at `0` because the default delivery method is buyer pickup, whose
  /// read-only fee is zero — the field must show the answer, not an empty box
  /// whose helper text claims there is no fee.
  final TextEditingController _deliveryFee = TextEditingController(text: '0');

  late final InquiryController _controller;

  String _subject = kInquiryGeneralSubject;
  bool? _purchaseInterest;
  InquiryTransactionMethod? _transactionMethod;

  /// Defaults to buyer pickup: the plan the schema's own examples describe,
  /// and the one that must not imply AgroBenta transports anything.
  InquiryDeliveryMethod _deliveryMethod = InquiryDeliveryMethod.buyerPickup;

  DateTime? _preferredSchedule;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    _message.dispose();
    _deliveryFee.dispose();
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
    if (_controller.state.isBusy) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final bool sent = await _controller.send(
      listingId: widget.listing.id,
      message: _message.text,
      subject: _subject,
      purchaseInterest: _purchaseInterest!,
      transactionMethod: _transactionMethod,
      deliveryMethod: _deliveryMethod,
      deliveryFee: _deliveryMethod == InquiryDeliveryMethod.arrangeDelivery
          ? _deliveryFee.text
          : null,
      contactMethod: InquiryContactMethod.inAppMessage,
      preferredSchedule: _preferredSchedule,
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

  void _setDeliveryMethod(InquiryDeliveryMethod? method) {
    if (method == null || method == _deliveryMethod) {
      return;
    }
    setState(() {
      _deliveryMethod = method;
      if (method == InquiryDeliveryMethod.buyerPickup) {
        // Shown, not sent: pickup carries no fee, so the read-only field
        // displays ₱0 and there is no nonzero value to contradict it.
        _deliveryFee.text = '0';
      } else {
        _deliveryFee.clear();
      }
    });
  }

  Future<void> _pickSchedule() async {
    final DateTime today = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _preferredSchedule ?? today,
      firstDate: today,
      // A two-year horizon: far enough to plan a purchase, close enough that
      // a typo cannot schedule an inquiry for 1970 or 2100. The server
      // accepts any date; this is a UI-only constraint (design spec §3.5
      // leaves past-date restrictions to approved requirements).
      lastDate: DateTime(today.year + 2, today.month, today.day),
    );
    if (picked != null && mounted) {
      setState(() => _preferredSchedule = picked);
    }
  }

  void _clearSchedule() {
    setState(() => _preferredSchedule = null);
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
          builder: (BuildContext context, Widget? child) => Text(
            _controller.state.status == InquiryUiStatus.succeeded
                ? 'Inquiry Sent'
                : 'Inquire About Livestock',
          ),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final InquiryState state = _controller.state;
            final bool isSubmitting = state.isBusy;

            // Must run on every state change, including one that only carries
            // `validationErrors` — see [_revealServerFieldErrors].
            _revealServerFieldErrors(state.validationErrors);

            if (state.status == InquiryUiStatus.succeeded) {
              return InquirySentView(
                listing: widget.listing,
                // Succeeded is published only from the create response, so
                // the record is present; the non-null assertion asserts that
                // controller invariant, not a hope.
                inquiry: state.inquiry!,
                // Back to Browse = the buyer shell underneath this stack.
                // Popping to the first route returns to the shell's IndexedStack
                // with its selected tab and scroll position intact — in every
                // path that reaches this screen that tab is Browse (design
                // spec §4.2).
                onBackToBrowse: () => Navigator.of(
                  context,
                ).popUntil((Route<dynamic> route) => route.isFirst),
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
                        ..._yourInquiry(isSubmitting),
                        const SizedBox(height: AppSpacing.md),
                        ..._transactionMethodSection(isSubmitting),
                        const SizedBox(height: AppSpacing.md),
                        ..._deliverySection(isSubmitting),
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

  List<Widget> _yourInquiry(bool isSubmitting) {
    return <Widget>[
      SectionCard(
        title: 'Your Inquiry',
        children: <Widget>[
          DropdownButtonFormField<String>(
            initialValue: _subject,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Subject',
              helperText: 'How the seller will see your inquiry filed.',
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: kInquiryGeneralSubject,
                child: Text(kInquiryGeneralSubject),
              ),
            ],
            onChanged: isSubmitting
                ? null
                : (String? value) => setState(
                    () => _subject = value ?? kInquiryGeneralSubject,
                  ),
            validator: (_) => _controller.state.errorFor('subject'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _message,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            minLines: 4,
            maxLines: 6,
            maxLength: kInquiryMessageMax,
            enabled: !isSubmitting,
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
              '${_message.text.length}/$kInquiryMessageMax',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Are you interested in purchasing? *',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xxs),
          FormField<bool>(
            initialValue: _purchaseInterest,
            validator: (bool? value) => value == null
                ? 'Please choose whether you are interested in purchasing.'
                : _controller.state.errorFor('purchase_interest'),
            builder: (FormFieldState<bool> field) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  IgnorePointer(
                    // `RadioGroup.onChanged` is non-nullable; the submitting
                    // state gates the whole group instead of the callback.
                    ignoring: isSubmitting,
                    child: RadioGroup<bool>(
                      groupValue: field.value,
                      onChanged: (bool? value) {
                        field.didChange(value);
                        setState(() => _purchaseInterest = value);
                      },
                      child: Column(
                        children: <Widget>[
                          RadioListTile<bool>(
                            value: true,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Yes'),
                          ),
                          RadioListTile<bool>(
                            value: false,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('No'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (field.hasError && field.errorText != null)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.xxs),
                      child: Text(
                        field.errorText!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ];
  }

  List<Widget> _transactionMethodSection(bool isSubmitting) {
    final ThemeData theme = Theme.of(context);

    return <Widget>[
      SectionCard(
        title: 'Transaction Method (Preferred)',
        children: <Widget>[
          Text(
            'Your preference only — this does not create a transaction, '
            'payment, or delivery booking.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _MethodCard(
                    selected:
                        _transactionMethod ==
                        InquiryTransactionMethod.directDeal,
                    icon: Icons.handshake_outlined,
                    title: 'Direct Deal',
                    subtitle: 'I will transact directly with the seller.',
                    enabled: !isSubmitting,
                    onTap: () => setState(
                      () => _transactionMethod =
                          InquiryTransactionMethod.directDeal,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _MethodCard(
                    selected:
                        _transactionMethod ==
                        InquiryTransactionMethod.arrangeDelivery,
                    icon: Icons.local_shipping_outlined,
                    title: 'Arrange Delivery',
                    subtitle: 'I will arrange for the transportation.',
                    enabled: !isSubmitting,
                    onTap: () => setState(
                      () => _transactionMethod =
                          InquiryTransactionMethod.arrangeDelivery,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (_controller.state.errorFor('transaction_method') != null)
            Text(
              _controller.state.errorFor('transaction_method')!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _deliverySection(bool isSubmitting) {
    final ThemeData theme = Theme.of(context);
    final bool isPickup = _deliveryMethod == InquiryDeliveryMethod.buyerPickup;

    return <Widget>[
      SectionCard(
        title: 'Delivery Details',
        children: <Widget>[
          DropdownButtonFormField<InquiryDeliveryMethod>(
            initialValue: _deliveryMethod,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Delivery Method'),
            items: const <DropdownMenuItem<InquiryDeliveryMethod>>[
              DropdownMenuItem<InquiryDeliveryMethod>(
                value: InquiryDeliveryMethod.buyerPickup,
                child: Text('Buyer Pickup (I will get the livestock)'),
              ),
              DropdownMenuItem<InquiryDeliveryMethod>(
                value: InquiryDeliveryMethod.arrangeDelivery,
                child: Text('Arrange Delivery (I will arrange transport)'),
              ),
            ],
            onChanged: isSubmitting ? null : _setDeliveryMethod,
            validator: (_) => _controller.state.errorFor('delivery_method'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _deliveryFee,
            // Read-only rather than disabled for pickup: the ₱0 stays visible
            // as the answer, while no keystroke can contradict it.
            readOnly: isPickup,
            enabled: !isSubmitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Delivery Fee (₱)',
              prefixText: isPickup ? null : '₱ ',
              helperText: isPickup
                  ? 'Buyer pickup — there is no delivery fee.'
                  : 'Optional. Your proposed fee, not a confirmed charge.',
              errorMaxLines: 2,
            ),
            validator: (String? value) =>
                (isPickup ? null : validateDeliveryFee(value)) ??
                _controller.state.errorFor('delivery_fee'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            initialValue: 'In-app Message',
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Preferred Contact Method',
              helperText: 'The seller replies through AgroBenta messages.',
              suffixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: isSubmitting ? null : _pickSchedule,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Preferred Schedule (Optional)',
                suffixIcon: _preferredSchedule == null
                    ? const Icon(Icons.calendar_today_outlined)
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear date',
                        onPressed: isSubmitting ? null : _clearSchedule,
                      ),
              ),
              child: Text(
                _preferredSchedule == null
                    ? 'No date chosen'
                    : AppFormatters.formatDate(_preferredSchedule),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _preferredSchedule == null
                      ? AppColors.textSecondary
                      : AppColors.text,
                ),
              ),
            ),
          ),
          if (_controller.state.errorFor('preferred_schedule') !=
              null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              _controller.state.errorFor('preferred_schedule')!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    ];
  }
}

/// One of the two selectable Transaction Method cards.
///
/// The selected state is carried three ways — border, tint, and
/// [Semantics.selected] — so it does not depend on colour alone (design spec
/// §3.4, §7).
class _MethodCard extends StatelessWidget {
  const _MethodCard({
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
