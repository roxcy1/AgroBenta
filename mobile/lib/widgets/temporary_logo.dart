import 'package:flutter/material.dart';

/// AgroBenta brand logo widget (reusable, size-configurable).
///
/// Uses the existing asset and preserves aspect ratio; no cropping/stretching.
class TemporaryLogo extends StatelessWidget {
  const TemporaryLogo({this.size = 56, super.key});

  /// Height (logical pixels). Width follows aspect ratio.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'AgroBenta logo',
      image: true,
      child: ExcludeSemantics(
        child: Image.asset(
          'assets/images/AgroBentaLogo.png',
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
