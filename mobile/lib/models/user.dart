import '../core/utils/json_utils.dart';

/// A user's account role, as stored in `users.role`.
///
/// This is a PHP backed enum serialised to its value by
/// `backend/app/Http/Resources/UserResource.php`. It is **server-owned**: the
/// app never sends `role` in any request and never grants it locally. It is
/// modelled here only so the client can render the consequence the server
/// decided on.
enum UserRole {
  /// A normal AgroBenta account. Every account created by mobile registration
  /// has this role, and it is the only role that may hold a mobile token.
  user('user'),

  /// An administrator. Administrators use the Admin Web, not this app — the
  /// backend refuses them a mobile token with a 403.
  admin('admin');

  const UserRole(this.value);

  /// The exact lowercase string the API sends.
  final String value;

  /// Parses the API value, failing loudly on an unknown one.
  ///
  /// A new role is a contract change, so it must surface as a
  /// [FormatException] rather than silently becoming a default.
  static UserRole fromValue(String value) {
    for (final UserRole role in UserRole.values) {
      if (role.value == value) {
        return role;
      }
    }
    throw FormatException('Unknown user role "$value".');
  }
}

/// Whether an account may act as a seller, as stored in
/// `users.seller_capability`.
///
/// This is the hinge of the single-account model: registering produces a
/// `buyer`, and only an approved seller verification flips this to `seller` —
/// performed by the server in `AdminSellerVerificationService`, never by the
/// app. The client reads it to decide what to render; it never writes it.
enum SellerCapability {
  /// A buyer account. This is what every new registration starts as.
  buyer('buyer'),

  /// A seller account, granted by the server once seller verification is
  /// approved. Seller verification itself is a later phase — GAP-07/GAP-08 —
  /// so this app has no way to reach this state yet.
  seller('seller');

  const SellerCapability(this.value);

  /// The exact lowercase string the API sends.
  final String value;

  /// Parses the API value, failing loudly on an unknown one.
  static SellerCapability fromValue(String value) {
    for (final SellerCapability capability in SellerCapability.values) {
      if (capability.value == value) {
        return capability;
      }
    }
    throw FormatException('Unknown seller capability "$value".');
  }
}

/// The authenticated user's own profile.
///
/// Mirrors `UserResource` field for field — no field is invented, and none is
/// omitted. Every field except `id`, `name` and `email` is nullable because
/// `UserResource` serialises them with `?->`, so a column that is `null` in
/// the database arrives as JSON `null` rather than being absent.
///
/// ## The four profile fields
///
/// `phone`, `location`, `avatar_url` and `bio` were added by the
/// `add_profile_fields_to_users_table` migration. They are the only fields the
/// mobile app can write through `PUT /api/profile`, and they arrive as JSON
/// `null` until the user fills them in — which is why they are nullable here
/// rather than carrying a default.
class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.sellerCapability,
    required this.emailVerifiedAt,
    required this.createdAt,
    required this.updatedAt,
    this.phone,
    this.location,
    this.avatarUrl,
    this.bio,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: readInt(json, 'id'),
      name: readString(json, 'name'),
      email: readString(json, 'email'),
      role: _readEnum(readNullableString(json, 'role'), UserRole.fromValue),
      sellerCapability: _readEnum(
        readNullableString(json, 'seller_capability'),
        SellerCapability.fromValue,
      ),
      emailVerifiedAt: readNullableDateTime(json, 'email_verified_at'),
      createdAt: readNullableDateTime(json, 'created_at'),
      updatedAt: readNullableDateTime(json, 'updated_at'),
      phone: readNullableString(json, 'phone'),
      location: readNullableString(json, 'location'),
      avatarUrl: readNullableString(json, 'avatar_url'),
      bio: readNullableString(json, 'bio'),
    );
  }

  /// `users.id` — an auto-increment integer.
  final int id;

  final String name;

  final String email;

  /// Server-owned. `null` only if the column is `null`, which the current
  /// migrations do not produce.
  final UserRole? role;

  /// Server-owned, and the only source of seller capability in the app.
  final SellerCapability? sellerCapability;

  /// Always `null` today: the backend has no email verification flow. Modelled
  /// because the resource sends the field.
  final DateTime? emailVerifiedAt;

  final DateTime? createdAt;

  final DateTime? updatedAt;

  /// Optional contact number. `null` until the user fills it in.
  ///
  /// Written through `PUT /api/profile`; the server accepts an empty string as
  /// a real "clear this field" value, so an empty string is not the same as
  /// `null` here.
  final String? phone;

  /// Optional town/city/province. `null` until the user fills it in.
  final String? location;

  /// Optional URL to an avatar image. `null` until the user sets one.
  ///
  /// A URL rather than an uploaded file: the backend has no upload endpoint
  /// (D-10 is still open), so the mobile client sends a link and the image is
  /// served by whatever the user hosted it on.
  final String? avatarUrl;

  /// Optional short biography. `null` until the user fills it in.
  final String? bio;

  /// Whether this account is an administrator.
  ///
  /// The backend already refuses an admin a mobile token, so a `true` here
  /// means the contract was violated rather than that the user is permitted
  /// anything. It exists for diagnostics; no screen branches on it to unlock
  /// behaviour.
  bool get isAdmin => role == UserRole.admin;

  /// Whether the server has granted seller capability.
  ///
  /// Until seller verification is built (GAP-07/GAP-08) this is `false` for
  /// every account this app can create.
  bool get isSeller => sellerCapability == SellerCapability.seller;

  /// Returns a copy with the given fields replaced.
  ///
  /// A named argument left out is left alone; passing `null` explicitly is the
  /// same as leaving it out, because the profile fields legitimately start as
  /// `null` and a "clear this field" is represented by sending an empty string
  /// to the server, not by nulling the local copy. Clearing is therefore the
  /// controller's job, and this method's job is only to merge a server
  /// response with what is already on screen.
  User copyWith({
    String? name,
    String? email,
    String? phone,
    String? location,
    String? avatarUrl,
    String? bio,
  }) {
    return User(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role,
      sellerCapability: sellerCapability,
      emailVerifiedAt: emailVerifiedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      phone: phone ?? this.phone,
      location: location ?? this.location,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
    );
  }

  /// Parses an optional enum column, tolerating `null` but rejecting an
  /// unrecognised value.
  static T? _readEnum<T>(String? value, T Function(String) fromValue) =>
      value == null ? null : fromValue(value);

  @override
  String toString() => 'User($id, $email, $role, $sellerCapability)';
}