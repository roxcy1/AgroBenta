import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_input_border.dart';

/// A text field's label, set flush with the left edge of its box.
///
/// Use it as `InputDecoration.label`. Material starts a floating label where
/// the field's text starts: after the content padding, or after the leading
/// icon when there is one. The approved design lines the label up with the
/// box instead, so this shifts it back by that distance. The shift is divided
/// by the floating label's scale because it is applied inside that scale.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {this.hasPrefixIcon = false, super.key});

  final String text;

  /// Whether the field has a `prefixIcon` (a [FieldIcon]). The label then
  /// starts after the icon slot rather than after the content padding.
  final bool hasPrefixIcon;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    final double inset = hasPrefixIcon
        ? AppInputs.iconSlotWidth
        : AppInputs.horizontalPadding;
    final double shift = inset / AppInputs.floatingLabelScale;

    return Transform.translate(
      offset: Offset(rtl ? shift : -shift, 0),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// A leading or trailing icon for a field that has a label.
///
/// Use it as `prefixIcon` / `suffixIcon`. Material centres those icons on the
/// whole field, label band included; the padding moves the icon down so it is
/// centred on the box, and the icon is drawn small and grey as in the
/// approved design. A field with no label uses a plain `Icon` instead.
class FieldIcon extends StatelessWidget {
  const FieldIcon(this.child, {super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppInputs.labelBand),
      child: SizedBox(
        width: AppInputs.iconSlotWidth,
        // As tall as the icon only, so the slot never stretches the field.
        child: Center(
          heightFactor: 1,
          child: IconTheme.merge(
            data: const IconThemeData(size: 20, color: AppColors.textHint),
            child: child,
          ),
        ),
      ),
    );
  }
}
