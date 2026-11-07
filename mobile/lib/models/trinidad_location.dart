import '../core/utils/json_utils.dart';

/// The backend-owned Trinidad location catalog returned to the mobile client.
class TrinidadLocationCatalog {
  const TrinidadLocationCatalog({
    required this.region,
    required this.province,
    required this.municipality,
    required this.barangays,
  });

  factory TrinidadLocationCatalog.fromJson(Map<String, dynamic> json) {
    return TrinidadLocationCatalog(
      region: readString(json, 'region'),
      province: readString(json, 'province'),
      municipality: readString(json, 'municipality'),
      barangays: readStringList(json, 'barangays'),
    );
  }

  final String region;
  final String province;
  final String municipality;
  final List<String> barangays;

  String get provinceLabel => '$region · $province';

  bool containsBarangay(String? name) =>
      name != null && barangays.contains(name);

  TrinidadLocation? createLocation({
    required String barangay,
    String streetPurok = '',
  }) {
    if (!containsBarangay(barangay)) return null;
    return TrinidadLocation(barangay: barangay, streetPurok: streetPurok);
  }

  /// Reconstructs a canonical address from a previously stored string.
  ///
  /// Unknown or legacy free-text addresses deliberately return `null`; callers
  /// show the original value and ask the user to choose rather than guessing a
  /// barangay.
  TrinidadLocation? parseAddress(String? raw) {
    final String address = (raw ?? '').trim();
    if (address.isEmpty) return null;

    for (final String barangay in barangays) {
      final String suffix = 'Barangay $barangay, $municipality, $province';
      if (address == suffix) {
        return TrinidadLocation(barangay: barangay, streetPurok: '');
      }

      final String marker = ', $suffix';
      if (address.endsWith(marker)) {
        final String street = address
            .substring(0, address.length - marker.length)
            .trim();
        if (street.isNotEmpty) {
          return TrinidadLocation(barangay: barangay, streetPurok: street);
        }
      }
    }

    return null;
  }
}

/// A form value for a Trinidad location.
///
/// The barangay stays nullable while a form is incomplete, so the shared
/// selector can report validation without inventing a selection. No barangay
/// code is included because the repository has no authoritative code dataset.
class TrinidadLocation {
  static const int sellerVerificationAddressMax = 191;
  static const int profileAddressMax = 191;
  static const int listingLocationMax = 255;

  const TrinidadLocation({this.barangay, this.streetPurok = ''});

  final String? barangay;
  final String streetPurok;

  bool get hasBarangay => barangay != null && barangay!.isNotEmpty;

  bool get isComplete => hasBarangay;

  /// Formats to the existing API/database string fields.
  String? formattedAddress({
    required String municipality,
    required String province,
  }) {
    if (!hasBarangay) return null;

    final List<String> parts = <String>[];
    final String street = streetPurok.trim();
    if (street.isNotEmpty) parts.add(street);
    parts.add('Barangay $barangay');
    parts.add(municipality);
    parts.add(province);
    return parts.join(', ');
  }

  TrinidadLocation copyWith({
    String? barangay,
    bool clearBarangay = false,
    String? streetPurok,
  }) {
    return TrinidadLocation(
      barangay: clearBarangay ? null : (barangay ?? this.barangay),
      streetPurok: streetPurok ?? this.streetPurok,
    );
  }
}
