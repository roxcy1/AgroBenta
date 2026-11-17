import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_fakes.dart';
import 'marketplace_fakes.dart';

/// One `MobileSellerProfileResource` payload, exactly as the backend serialises
/// it.
///
/// Field names, nullability and value spellings are copied from
/// `backend/app/Http/Resources/MobileSellerProfileResource.php`. The payload
/// deliberately has no `email`, `phone`, raw `location` or verification
/// document — the public projection has no such fields.
Map<String, dynamic> sellerProfileJson({
  Object? id = 3,
  String name = 'Joseph Basilad',
  Object? avatarUrl,
  Object? bio,
  bool isVerified = true,
  Object? publicLocation = 'Barangay San Isidro, Trinidad, Bohol',
  Object? memberSince = '2026-09-20T08:15:00.000000Z',
  Object? activeListingsCount = 1,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'avatar_url': avatarUrl,
    'bio': bio,
    'is_verified': isVerified,
    'public_location': publicLocation,
    'member_since': memberSince,
    'active_listings_count': activeListingsCount,
  };
}

/// A successful `GET /marketplace/sellers/{seller}`.
http.Response sellerProfileResponse({
  Map<String, dynamic>? profile,
  int statusCode = 200,
}) => http.Response(
  jsonEncode(successEnvelope(data: profile ?? sellerProfileJson())),
  statusCode,
  headers: const <String, String>{'content-type': 'application/json'},
);

/// The `404` a non-public or deleted seller produces.
http.Response sellerNotFoundResponse({String message = 'Seller not found.'}) =>
    http.Response(jsonEncode(message), 404);

/// A successful `GET /marketplace/sellers/{seller}/listings`.
http.Response sellerListingsResponse({
  List<Map<String, dynamic>>? listings,
  int currentPage = 1,
  int lastPage = 1,
  int perPage = 15,
  int total = 1,
  int statusCode = 200,
}) => http.Response(
  jsonEncode(
    successEnvelope(
      data: marketplacePageJson(
        listings: listings,
        currentPage: currentPage,
        lastPage: lastPage,
        perPage: perPage,
        total: total,
      ),
    ),
  ),
  statusCode,
  headers: const <String, String>{'content-type': 'application/json'},
);
