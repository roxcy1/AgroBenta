import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../state/transaction_timeline.dart';

/// The vertical progress tracker for a purchase request.
///
/// Renders [TransactionTimeline.stepsFor] verbatim. It does **not** decide the
/// steps or invent dates: each marker's title, detail and state come from the
/// record's real current status. No line shows a date, because the backend
/// stores no per-step timestamps.
class TransactionProgressTimeline extends StatelessWidget {
  const TransactionProgressTimeline({required this.steps, super.key});

  final List<TimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < steps.length; i++)
          _TimelineRow(
            step: steps[i],
            isFirst: i == 0,
            isLast: i == steps.length - 1,
            // A connector is "reached" only when the step above it is done.
            connectorReached:
                steps[i].state == TimelineStepState.completed ||
                steps[i].state == TimelineStepState.current,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.step,
    required this.isFirst,
    required this.isLast,
    required this.connectorReached,
  });

  final TimelineStep step;
  final bool isFirst;
  final bool isLast;
  final bool connectorReached;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final _MarkerStyle style = _MarkerStyle.forState(step.state);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              _Marker(style: style),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: connectorReached
                        ? style.color.withValues(alpha: 0.5)
                        : AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                top: 2,
                bottom: isLast ? 0 : AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    step.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: style.color,
                      fontWeight: step.state == TimelineStepState.current
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(step.detail, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The resolved colours and icon for one marker state.
class _MarkerStyle {
  const _MarkerStyle({
    required this.color,
    required this.icon,
    required this.filled,
  });

  final Color color;
  final IconData icon;
  final bool filled;

  static _MarkerStyle forState(TimelineStepState state) {
    return switch (state) {
      TimelineStepState.completed => const _MarkerStyle(
        color: AppColors.success,
        icon: Icons.check,
        filled: true,
      ),
      TimelineStepState.current => const _MarkerStyle(
        color: AppColors.primary,
        icon: Icons.circle,
        filled: true,
      ),
      TimelineStepState.upcoming => const _MarkerStyle(
        color: AppColors.textSecondary,
        icon: Icons.circle_outlined,
        filled: false,
      ),
      // A terminal exit that did not happen. Error-tinted but explicitly not a
      // success marker, so a cancelled record never reads as completed.
      TimelineStepState.unreached => const _MarkerStyle(
        color: AppColors.error,
        icon: Icons.close,
        filled: false,
      ),
    };
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.style});

  final _MarkerStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: style.filled
            ? style.color.withValues(alpha: 0.14)
            : AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: style.filled
              ? style.color
              : style.color.withValues(alpha: 0.5),
          width: style.filled ? 1.5 : 1.5,
        ),
      ),
      child: Icon(
        style.icon,
        size: style.icon == Icons.circle ? 10 : 16,
        color: style.color,
      ),
    );
  }
}
