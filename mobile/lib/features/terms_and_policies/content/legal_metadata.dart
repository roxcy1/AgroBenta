/// Operator-provided legal details shared by the bundled draft documents.
///
/// Leave dates null until the operator approves the text and sets its effective
/// and review dates. The detail screen intentionally omits unconfirmed dates.
abstract final class LegalMetadata {
  static const bool isDraft = true;

  static const String operatorName = 'Pending operator confirmation';
  static const String operatorAddress = 'Pending operator confirmation';
  static const String generalContact = 'Pending contact details';
  static const String privacyContact = 'Pending privacy contact details';
  static const String dataProtectionContact = 'Pending designation';

  static const String? effectiveDate = null;
  static const String? lastUpdatedDate = null;

  static const String draftNotice =
      'Draft for operator and legal review. These documents are not approved '
      'final policies. Confirm the operator details, contact channels, legal '
      'terms and effective dates before public deployment.';
}
