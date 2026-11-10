import 'package:flutter/material.dart';

/// The silhouette for a livestock type, tinted to [color].
///
/// The four catalogue types have their own artwork in
/// `assets/icons/livestock/`. They replace the Font Awesome stand-ins (a hippo
/// for carabao, bacon for swine, a paw for goat) that were a reported visual
/// compromise. Any other type falls back to a neutral paw.
class LivestockTypeIcon extends StatelessWidget {
  const LivestockTypeIcon({
    required this.type,
    this.size = 24,
    this.color,
    super.key,
  });

  /// The catalogue `livestock_type` value, e.g. `cattle`.
  final String type;
  final double size;

  /// Defaults to the ambient icon colour.
  final Color? color;

  static const Set<String> _illustrated = <String>{
    'cattle',
    'carabao',
    'goat',
    'swine',
  };

  /// Whether [type] has its own artwork rather than the fallback.
  static bool hasArtwork(String type) =>
      _illustrated.contains(type.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    final String key = type.trim().toLowerCase();
    if (!_illustrated.contains(key)) {
      return Icon(Icons.pets_outlined, size: size, color: color);
    }
    return ImageIcon(
      AssetImage('assets/icons/livestock/$key.png'),
      size: size,
      color: color,
    );
  }
}
