import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/user_report.dart';
import '../../../widgets/field_label.dart';
import '../../../widgets/initials_avatar.dart';
import '../../../widgets/local_image_preview.dart';
import '../../../widgets/notice_banner.dart';
import '../../../widgets/section_card.dart';
import '../state/report_user_controller.dart';
import '../state/report_user_state.dart';
import '../state/user_report_scope.dart';

/// The one report form shared by the seller profile, chat, and transaction
/// entry points.
class ReportUserScreen extends StatefulWidget {
  const ReportUserScreen({
    required this.reportedUserId,
    required this.reportedUserName,
    required this.currentUserId,
    this.reportedUserRole,
    this.imagePicker,
    super.key,
  });

  final int reportedUserId;
  final String reportedUserName;
  final int currentUserId;

  /// `Seller`, `Buyer`, or null when the caller does not know.
  final String? reportedUserRole;

  /// Injectable for tests; production creates the plugin-backed picker.
  final ImagePicker? imagePicker;

  @override
  State<ReportUserScreen> createState() => _ReportUserScreenState();
}

class _ReportUserScreenState extends State<ReportUserScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _description = TextEditingController();
  late final ReportUserController _controller;
  late final ImagePicker _imagePicker;

  UserReportReason? _reason;
  XFile? _evidence;
  String? _evidenceError;

  bool get _isSelf => widget.currentUserId == widget.reportedUserId;

  @override
  void initState() {
    super.initState();
    _controller = ReportUserController(
      UserReportScope.readOf(context),
      widget.reportedUserId,
    );
    _imagePicker = widget.imagePicker ?? ImagePicker();
  }

  @override
  void dispose() {
    _description.dispose();
    _controller.dispose();
    super.dispose();
  }

  String? _fieldError(String field) {
    final List<String>? errors = _controller.state.fieldErrors[field];
    return errors == null || errors.isEmpty ? null : errors.first;
  }

  Future<void> _pickEvidence() async {
    final XFile? picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null || !mounted) {
      return;
    }

    final String name = picked.name.toLowerCase();
    if (!name.endsWith('.jpg') &&
        !name.endsWith('.jpeg') &&
        !name.endsWith('.png') &&
        !name.endsWith('.webp')) {
      setState(() {
        _evidenceError = 'Choose a JPEG, PNG, or WebP image.';
      });
      return;
    }

    final int length = await picked.length();
    if (!mounted) {
      return;
    }
    if (length > 5 * 1024 * 1024) {
      setState(() {
        _evidenceError = 'The screenshot must be 5 MB or smaller.';
      });
      return;
    }

    setState(() {
      _evidence = picked;
      _evidenceError = null;
    });
  }

  Future<void> _submit() async {
    if (_isSelf) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_evidenceError != null) {
      return;
    }

    final UserReportReason? reason = _reason;
    if (reason == null) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Submit this report?'),
        content: Text(
          'Your report about ${widget.reportedUserName} will be sent to an '
          'administrator for review. False or abusive reports may affect your '
          'account.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit Report'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final bool submitted = await _controller.submit(
      reason: reason,
      description: _description.text,
      evidence: _evidence,
    );

    if (!submitted || !mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report submitted for administrator review.')),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Report User')),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final ReportUserState state = _controller.state;
            final bool isSubmitting = state.isSubmitting;

            return Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  AppSpacing.md,
                  AppSpacing.screenGutter,
                  AppSpacing.xl,
                ),
                children: <Widget>[
                  SectionCard(
                    title: 'Reported user',
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          InitialsAvatar(
                            name: widget.reportedUserName,
                            radius: 22,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  widget.reportedUserName,
                                  style: theme.textTheme.titleMedium,
                                ),
                                if (widget.reportedUserRole != null)
                                  Text(
                                    widget.reportedUserRole!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_isSelf) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    NoticeBanner(
                      accent: AppColors.error,
                      icon: Icons.block_outlined,
                      message: 'You cannot report your own account.',
                    ),
                  ],
                  if (state.errorMessage != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    NoticeBanner(
                      accent: AppColors.error,
                      icon: Icons.error_outline,
                      message: state.errorMessage!,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  DropdownButtonFormField<UserReportReason>(
                    icon: const FieldDropdownIcon(),
                    initialValue: _reason,
                    isExpanded: true,
                    decoration: InputDecoration(
                      label: const FieldLabel('Reason'),
                      errorText: _fieldError('reason'),
                    ),
                    items: UserReportReason.values
                        .map(
                          (UserReportReason reason) =>
                              DropdownMenuItem<UserReportReason>(
                                value: reason,
                                child: Text(
                                  reason.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                        )
                        .toList(growable: false),
                    onChanged: isSubmitting || _isSelf
                        ? null
                        : (UserReportReason? value) =>
                              setState(() => _reason = value),
                    validator: (UserReportReason? value) =>
                        value == null ? 'Select a reason.' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _description,
                    enabled: !isSubmitting && !_isSelf,
                    minLines: 5,
                    maxLines: 8,
                    maxLength: 2000,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      label: const FieldLabel('What happened?'),
                      hintText: 'Describe the incident clearly and factually.',
                      alignLabelWithHint: true,
                      errorText: _fieldError('description'),
                    ),
                    validator: (String? value) {
                      if (value == null || value.trim().length < 10) {
                        return 'Describe the incident in at least 10 characters.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SectionCard(
                    title: 'Evidence (optional)',
                    children: <Widget>[
                      if (_evidence == null)
                        Text(
                          'Attach one screenshot that supports the report. '
                          'JPEG, PNG, or WebP, up to 5 MB.',
                          style: theme.textTheme.bodySmall,
                        )
                      else ...<Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: SizedBox(
                            height: 170,
                            child: LocalImagePreview(
                              file: _evidence!,
                              fallback: const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      if (_evidenceError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Text(
                            _evidenceError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: isSubmitting || _isSelf
                                ? null
                                : _pickEvidence,
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                            label: Text(
                              _evidence == null
                                  ? 'Attach Screenshot'
                                  : 'Replace Screenshot',
                            ),
                          ),
                          if (_evidence != null)
                            TextButton(
                              onPressed: isSubmitting || _isSelf
                                  ? null
                                  : () => setState(() {
                                      _evidence = null;
                                      _evidenceError = null;
                                    }),
                              child: const Text('Remove'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: isSubmitting || _isSelf ? null : _submit,
                    child: isSubmitting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit Report'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
