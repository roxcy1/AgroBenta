/// Input checks shared by the sign-in and registration forms.
///
/// These are deliberately thin. They answer "is this worth sending to the
/// server?", not "will the server accept it?". A duplicate email, an address
/// that fails Laravel's stricter `email` rule and a rejected password all come
/// back as `422` and are mapped from `ApiException.validationErrors` — the
/// server is the authority on those, and guessing at them here would only
/// produce a second, worse copy of the same rules.
///
/// Client-side checks exist for one reason: to avoid a pointless round trip on
/// an empty field, and to warn about the password minimum before the user
/// waits for a response.
library;

/// Mirrors `password` `min:8` in `backend/app/Http/Requests/Auth/RegisterRequest.php`.
const int minimumPasswordLength = 8;

String? validateRequiredEmail(String? value) {
  final String email = value?.trim() ?? '';
  if (email.isEmpty) {
    return 'Enter your email address.';
  }
  if (!email.contains('@')) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? validateRequiredPassword(String? value) =>
    (value == null || value.isEmpty) ? 'Enter your password.' : null;

String? validatePasswordLength(String? value) {
  if (value == null || value.isEmpty) {
    return 'Enter a password.';
  }
  if (value.length < minimumPasswordLength) {
    return 'Use at least $minimumPasswordLength characters.';
  }
  return null;
}
