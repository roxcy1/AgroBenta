import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// A person's round avatar: their photo, or their initials on brand green.
///
/// The approved design shows every person without a photo the same way — a
/// solid green circle with up to two white initials — so the fallback lives
/// here rather than being restyled per screen.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    required this.name,
    this.imageUrl,
    this.radius = 23,
    super.key,
  });

  final String name;

  /// The person's photo. Null or blank shows the initials.
  final String? imageUrl;

  final double radius;

  /// Up to two initials: the first letter of the first and of the last word.
  /// A blank name gives `?`.
  static String initialsOf(String name) {
    final List<String> words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return '?';
    }
    final String first = words.first.substring(0, 1);
    if (words.length == 1) {
      return first.toUpperCase();
    }
    return (first + words.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final String? url = imageUrl;
    if (url != null && url.trim().isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(url));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary,
      child: Text(
        initialsOf(name),
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.66,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}
