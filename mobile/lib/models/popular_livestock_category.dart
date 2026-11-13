import '../core/utils/json_utils.dart';

/// One ranked category on Buyer Home, from
/// `GET /api/marketplace/popular-livestock`.
///
/// Mirrors `PopularLivestockCategoryResource`: the canonical category name, the
/// number of genuinely completed sales in the 30-day window, and one
/// representative listing photo (already an absolute URL) when one exists.
class PopularLivestockCategory {
  const PopularLivestockCategory({
    required this.livestockType,
    required this.completedSales,
    required this.photoUrl,
  });

  factory PopularLivestockCategory.fromJson(Map<String, dynamic> json) {
    return PopularLivestockCategory(
      livestockType: readString(json, 'livestock_type'),
      completedSales: readInt(json, 'completed_sales'),
      photoUrl: readNullableString(json, 'photo_url'),
    );
  }

  final String livestockType;
  final int completedSales;
  final String? photoUrl;

  String get salesLabel => completedSales == 1
      ? '1 completed sale'
      : '$completedSales completed sales';
}
