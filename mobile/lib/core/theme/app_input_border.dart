import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Shared measurements for text fields, per the approved mobile design: a
/// label above a 46dp box with 14dp side padding.
abstract final class AppInputs {
  /// Height kept above a labelled field's box for its label: the 13sp label
  /// line and a 6dp gap.
  static const double labelBand = 23;

  /// Padding inside the box, left and right.
  static const double horizontalPadding = 14;

  /// Padding inside the box, top and bottom.
  static const double verticalPadding = 12;

  /// The space Material leaves between a leading icon and the text.
  static const double prefixIconGap = 4;

  /// Width reserved for a leading or trailing icon inside the box.
  static const double iconSlotWidth = 44;

  /// Material's fixed scale for a floating label.
  static const double floatingLabelScale = 0.75;

  /// The label's size on screen.
  static const double labelFontSize = 13;

  /// The theme's content padding. There is no top padding: on a labelled
  /// field Material puts the label at the very top and starts the text
  /// [labelledTextTop] below it (see [inlineLabelFontSize]).
  static const EdgeInsets labelledPadding = EdgeInsets.fromLTRB(
    horizontalPadding,
    0,
    horizontalPadding,
    verticalPadding,
  );

  /// Content padding for a field with **no** label (a search box, a bare
  /// amount). Pass it as `contentPadding`, because the theme default assumes
  /// a label and so has no top padding.
  static const EdgeInsets plainPadding = EdgeInsets.symmetric(
    horizontal: horizontalPadding,
    vertical: verticalPadding,
  );

  /// Where a labelled field's text starts, measured from the field's top.
  static const double labelledTextTop = labelBand + verticalPadding;

  /// The font size given to the theme's *inline* label style.
  ///
  /// The inline style is never drawn (labels always float), but Material
  /// derives the distance from a floating label to the text from it:
  /// `4 + 0.75 × fontSize`. This is that formula solved for
  /// [labelledTextTop], which is what puts the text inside the box.
  static const double inlineLabelFontSize =
      (labelledTextTop - 4) / floatingLabelScale;
}

/// The approved design's field outline: the label sits **above** a plain
/// rounded box instead of in a notch cut into the box's top edge.
///
/// It is deliberately not an "outline" border in Material's sense
/// ([isOutline] is false). That makes Material lay a labelled field out as
/// label first, text below it, and keep a field with no label compact, so
/// every `InputDecoration` in the app keeps working and a field's label stays
/// part of the field for tests and screen readers. This class then draws the
/// box [AppInputs.labelBand] below the top whenever the field has a label,
/// and at the full height when it has none.
///
/// It also paints the box's fill, because Material would fill the whole
/// field, label band included. The theme therefore leaves `filled` off.
class LabelAboveInputBorder extends OutlineInputBorder {
  const LabelAboveInputBorder({
    super.borderSide = const BorderSide(color: AppColors.fieldBorder),
    super.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.sm)),
    this.fillColor = AppColors.surface,
    // No gap: Material would otherwise inset the text and label a further
    // 4dp beyond the content padding.
  }) : super(gapPadding: 0);

  /// The colour inside the box.
  final Color fillColor;

  @override
  bool get isOutline => false;

  @override
  LabelAboveInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
    Color? fillColor,
  }) {
    return LabelAboveInputBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
      fillColor: fillColor ?? this.fillColor,
    );
  }

  @override
  LabelAboveInputBorder scale(double t) {
    return LabelAboveInputBorder(
      borderSide: borderSide.scale(t),
      borderRadius: borderRadius * t,
      fillColor: fillColor,
    );
  }

  // The focus and error transitions interpolate between two borders. Without
  // these overrides the in-between frames would be plain outlined borders,
  // and the notch would flash while the animation runs.
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is LabelAboveInputBorder) {
      return LabelAboveInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        fillColor: Color.lerp(a.fillColor, fillColor, t)!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is LabelAboveInputBorder) {
      return LabelAboveInputBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
        fillColor: Color.lerp(fillColor, b.fillColor, t)!,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    // The decorator reports a gap only when the field has a label, which is
    // exactly when the box has to start below the label band.
    final bool hasLabel = gapExtent > 0;
    final Rect box = hasLabel
        ? Rect.fromLTRB(
            rect.left,
            rect.top + AppInputs.labelBand,
            rect.right,
            rect.bottom,
          )
        : rect;

    final RRect outer = borderRadius.toRRect(box);
    canvas.drawRRect(outer, Paint()..color = fillColor);
    if (borderSide.style != BorderStyle.none && borderSide.width > 0) {
      canvas.drawRRect(
        outer.deflate(borderSide.width / 2.0),
        borderSide.toPaint(),
      );
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is LabelAboveInputBorder &&
        other.borderSide == borderSide &&
        other.borderRadius == borderRadius &&
        other.fillColor == fillColor;
  }

  @override
  int get hashCode => Object.hash(borderSide, borderRadius, fillColor);
}
