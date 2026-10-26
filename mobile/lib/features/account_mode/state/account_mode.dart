/// The two views of the same AgroBenta account.
///
/// Mode is a display choice only. It never grants seller capability and is
/// never sent to the server; the backend authorises seller actions from
/// `seller_capability` alone.
enum AccountMode {
  /// Browse and purchase livestock.
  buyer,

  /// List and manage livestock. Available only to verified sellers.
  seller,
}
