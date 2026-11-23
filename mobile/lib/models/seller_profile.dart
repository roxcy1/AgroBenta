import '../core/utils/json_utils.dart';

/// The public seller profile behind the seller card on Listing Details.
///
/// Mirrors `backend/app/Http/Resources/MobileSellerProfileResource.php`
/// field for field. There is deliberately **no** `email`, `phone`, raw
/// `location`, verification document or administrative field: the resource is a
/// public projection and the client must not model data the server refuses to
/// disclose.
///
/// `public_location` is the server's already-reduced barangay address
/// (`Barangay San Isidro, Trinidad, Bohol`). Never reconstruct a sharper
/// location from it, and never expect the account's full address.
class SellerProfile {
  const SellerProfile({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.bio,
    required this.isVerified,
    required this.publicLocation,
    required this.memberSince,
    required this.activeListingsCount,
  });

  factory SellerProfile.fromJson(Map<String, dynamic> json) {
    return SellerProfile(
      id: readInt(json, 'id'),
      name: readString(json, 'name'),
      avatarUrl: readNullableString(json, 'avatar_url'),
      bio: readNullableString(json, 'bio'),
      isVerified: readNullableBool(json, 'is_verified') ?? false,
      publicLocation: readNullableString(json, 'public_location'),
      memberSince: readNullableDateTime(json, 'member_since'),
      activeListingsCount: readInt(json, 'active_listings_count'),
    );
  }

  /// `users.id`.
  final int id;

  /// The seller's display name.
  final String name;

  /// Optional profile photo. Null or blank renders initials.
  final String? avatarUrl;

  /// Optional seller-authored biography, already public by the account's own
  /// choice through the profile editor.
  final String? bio;

  /// The server's verification decision (`seller_capability == seller`).
  /// Only an approved seller is ever shown the Verified Seller badge.
  final bool isVerified;

  /// Barangay-level public location, e.g. `Barangay San Isidro, Trinidad,
  /// Bohol`. Null when the account has no parseable public address.
  final String? publicLocation;

  /// The account's creation date. This is "member since", not the date the
  /// seller was approved.
  final DateTime? memberSince;

  /// The seller's marketplace-visible listing count, computed server-side with
  /// the same rules as the Listings tab.
  final int activeListingsCount;

  /// Whether there is a biography worth rendering.
  bool get hasBio => (bio ?? '').trim().isNotEmpty;

  /// Whether a public location is available.
  bool get hasPublicLocation => (publicLocation ?? '').trim().isNotEmpty;

  @override
  String toString() =>
      'SellerProfile($id, $name, verified: $isVerified, '
      '$activeListingsCount active)';
}
