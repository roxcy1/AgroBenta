import 'package:flutter/material.dart';

import '../model/legal_document.dart';
import 'legal_metadata.dart';

/// Eight system-specific legal drafts, bundled for offline reading.
///
/// The documents describe implemented application behavior and identify
/// unresolved operational/legal details for review. They do not represent legal
/// advice or a claim of regulatory compliance.
abstract final class LegalDocuments {
  static const List<LegalDocument> all = <LegalDocument>[
    termsAndConditions,
    privacyPolicy,
    sellerPolicy,
    buyerPolicy,
    livestockListingPolicy,
    transactionAndCancellationPolicy,
    communityAndMessagingPolicy,
    aiPriceSuggestionDisclaimer,
  ];

  static const LegalDocument termsAndConditions = LegalDocument(
    id: 'terms-and-conditions',
    title: 'Terms and Conditions',
    description: 'How the AgroBenta marketplace works and what users agree to.',
    icon: Icons.description_outlined,
    introduction:
        'These draft Terms describe use of AgroBenta, a mobile application '
        'that helps livestock buyers and sellers in Trinidad, Bohol discover '
        'listings, communicate, make offers and record transaction progress. '
        'The operator identity and final legal wording must be confirmed before '
        'these Terms take effect.',
    sections: <LegalSection>[
      LegalSection(
        heading: 'Purpose and AgroBenta’s role',
        paragraphs: <String>[
          'AgroBenta provides software for user accounts, seller verification, '
              'livestock listings, buyer inquiries, seller offers, messaging, '
              'transaction records, fulfillment updates, notifications, reports '
              'and AI-assisted price suggestions. Buyers and sellers remain '
              'responsible for the livestock sale and for arrangements they make '
              'with each other.',
          'AgroBenta does not own or take custody of listed livestock. The app '
              'does not inspect animals, guarantee a listing or transaction, '
              'provide insurance or escrow, process payments, or provide or book '
              'transportation. A recorded payment preference, handover stage or '
              'receipt confirmation is not independent proof that payment or '
              'delivery occurred.',
        ],
      ),
      LegalSection(
        heading: 'Eligibility and account registration',
        paragraphs: <String>[
          'Users register with a name, email address and password, or may use '
              'Google sign-in where it is available. Every new account begins with '
              'buyer capability. A person uses one account for buyer and seller '
              'activity; seller capability is granted only after administrator '
              'approval of seller verification.',
          'The application does not currently verify a user’s age. The '
              'minimum-age and guardian-consent rules must be confirmed by the '
              'operator and legal counsel before publication. Do not publish a '
              'specific age requirement until that review is complete.',
        ],
      ),
      LegalSection(
        heading: 'Account security and responsibilities',
        bullets: <String>[
          'Provide accurate account information and keep sign-in credentials '
              'private. Do not impersonate another person or share an account '
              'in a way that misrepresents who is acting.',
          'Use the account only for activity you are authorized to conduct. '
              'Tell the confirmed AgroBenta support contact promptly if you '
              'suspect unauthorized access.',
          'The mobile application uses authenticated accounts and the server '
              'checks permissions for protected actions. Users remain '
              'responsible for activity made through their signed-in account.',
        ],
      ),
      LegalSection(
        heading: 'Marketplace and user responsibilities',
        paragraphs: <String>[
          'AgroBenta displays seller-submitted livestock information and '
              'facilitates communication. Seller verification records an '
              'administrator’s approval status; it does not prove ownership, '
              'animal health, listing accuracy, seller conduct or transaction '
              'success.',
          'Sellers are responsible for lawful authority to sell, accurate '
              'descriptions, price and available quantity, required disclosures, '
              'and honoring accepted transaction terms. Buyers are responsible '
              'for reviewing listings, asking questions, inspecting livestock '
              'where appropriate, and deciding whether to proceed.',
        ],
      ),
      LegalSection(
        heading: 'Acceptable use and prohibited conduct',
        paragraphs: <String>[
          'Use AgroBenta respectfully and only for lawful livestock '
              'marketplace activity. Users must not:',
        ],
        bullets: <String>[
          'post false, misleading, unauthorized or unavailable livestock '
              'listings;',
          'commit or solicit scams, fraudulent payment activity or '
              'impersonation;',
          'harass, threaten, spam or send abusive or inappropriate content;',
          'publish another person’s private information without authority, '
              'or attempt to access another user’s account or records;',
          'misuse the app, interfere with its operation or evade applicable '
              'law or administrator moderation.',
        ],
      ),
      LegalSection(
        heading: 'Transactions and user arrangements',
        paragraphs: <String>[
          'An inquiry communicates interest and does not create a transaction '
              'or reserve livestock. A seller may issue a formal offer from an '
              'eligible inquiry. Accepting that offer creates a pending transaction '
              'and reserves the agreed quantity. The app also provides a direct '
              'purchase action that creates a pending transaction and reserves '
              'quantity. Payment and collection arrangements are made by the '
              'parties directly.',
          'The seller reports preparation and pickup or delivery progress. The '
              'buyer confirms receipt after the seller records handover. Users '
              'must check the transaction and cancellation rules before acting. '
              'AgroBenta does not promise refunds, payment recovery, dispute '
              'resolution or delivery.',
        ],
      ),
      LegalSection(
        heading: 'Account restrictions and deactivation',
        paragraphs: <String>[
          'AgroBenta provides reporting and administrator moderation. An '
              'administrator can deactivate an account; the implemented process '
              'retains associated business history and revokes access. This draft '
              'does not set a new appeal procedure or response deadline. Any final '
              'restriction and appeal wording requires operator/legal approval.',
        ],
      ),
      LegalSection(
        heading: 'Availability and changes',
        paragraphs: <String>[
          'Some features depend on network access and configured services and '
              'may be unavailable or return no result. The operator may maintain '
              'or update the application. The final notice process and version '
              'effective dates must be confirmed before publication.',
        ],
      ),
      LegalSection(
        heading: 'Intellectual property and user content',
        paragraphs: <String>[
          'AgroBenta names, logos, software and other brand materials belong '
              'to their respective rights holders. Do not copy or use them without '
              'permission. Upload or submit only listing text, photographs and '
              'other material that you own or are authorized to share.',
          'The exact license users grant the operator to store, reproduce and '
              'display submitted content for marketplace operation must be '
              'approved by the operator and legal counsel before these Terms are '
              'finalized.',
        ],
      ),
      LegalSection(
        heading: 'Liability and governing law',
        paragraphs: <String>[
          'Listings, estimates and user communications are not independent '
              'verification or guarantees. Nothing in these draft Terms is intended '
              'to remove rights or liabilities that cannot lawfully be excluded. '
              'Any final limitation-of-liability language and its application to '
              'AgroBenta’s operator require legal review.',
          'The project operates in the Philippines. Philippine law is the '
              'proposed governing law, subject to counsel confirming the final '
              'clause and any required complaint or dispute venue.',
          'The operator must obtain advice on how RA 11967 (Internet '
              'Transactions Act), RA 7394 (Consumer Act) and RA 8792 (Electronic '
              'Commerce Act) apply to this platform and the individual livestock '
              'sales. This draft does not determine AgroBenta’s legal '
              'classification, claim compliance or limit any rights provided by '
              'law.',
        ],
      ),
      LegalSection(
        heading: 'Contact and policy updates',
        paragraphs: <String>[
          'Operator: ${LegalMetadata.operatorName}. Address: '
              '${LegalMetadata.operatorAddress}. Support: '
              '${LegalMetadata.generalContact}. These details must be supplied '
              'before publication.',
          'AgroBenta will show the confirmed effective and last-updated dates '
              'after approval. The current draft has no effective date.',
        ],
      ),
    ],
  );

  static const LegalDocument privacyPolicy = LegalDocument(
    id: 'privacy-policy',
    title: 'Privacy Policy',
    description: 'What information AgroBenta uses and how it is handled.',
    icon: Icons.privacy_tip_outlined,
    introduction:
        'This draft explains personal information handled by AgroBenta’s '
        'implemented mobile and backend features. The controller identity, '
        'lawful bases, processors, retention schedule and privacy contact must '
        'be confirmed by the operator and privacy counsel before publication. '
        'It is not a claim of compliance with Republic Act No. 10173.',
    sections: <LegalSection>[
      LegalSection(
        heading: 'Who is responsible',
        paragraphs: <String>[
          'The personal information controller is the legal person or '
              'organization that determines why and how information is processed. '
              'AgroBenta’s operator and controller identity have not been supplied '
              'to this app. The confirmed name, address and privacy contact must '
              'appear here before use.',
          'This draft is informed by the transparency, legitimate-purpose, '
              'proportionality, retention, data-subject-rights and security '
              'principles in the Philippine Data Privacy Act of 2012 (RA 10173). '
              'Mentioning the law does not establish that the system is compliant.',
        ],
      ),
      LegalSection(
        heading: 'Information the system handles',
        bullets: <String>[
          'Account and profile: name, email, password credential, phone, '
              'optional profile location, avatar and bio. Passwords are stored '
              'using Laravel’s password-hashing facility, not returned in the '
              'user resource.',
          'Seller verification: phone, address, optional business details, '
              'government-ID type and reference, ID images, proof of address, '
              'selfie, optional farm photos, review outcome and administrator '
              'note.',
          'Marketplace content: livestock category, breed, age, sex, weight, '
              'quantity, asking price, health and vaccination information, '
              'description, listing location and photos.',
          'Communications and sales: inquiries and preferences, messages, '
              'offers, transaction quantity, agreed amount, payment and '
              'collection preferences, fulfillment status, receipt snapshot '
              'and related notifications.',
          'Receipt gallery export: a buyer may choose Save to Gallery for a '
              'completed transaction receipt. The app captures the receipt '
              'displayed on screen and saves a PNG copy in the device photo '
              'library. It may contain the receipt reference, completion date, '
              'buyer and seller names, livestock type and breed, quantity, agreed '
              'total, fulfillment method and recorded payment preference. This '
              'user-initiated export writes to the device gallery and does not '
              'upload the image to the AgroBenta backend. Take care when storing '
              'or sharing receipt images.',
          'Safety and support: account reports, report reason and description, '
              'optional evidence image, moderation outcomes and system '
              'activity records.',
          'Device and service information: an Android Firebase Cloud '
              'Messaging registration token for push notifications, notification '
              'preferences, and information needed to sign in or use configured '
              'services. A complete inventory of operational logs and device '
              'data requires operator confirmation.',
          'Price suggestion inputs and results: the prediction service receives '
              'livestock type, breed, sex, age and weight and the backend stores '
              'an input snapshot, estimate, status, basis and provider metadata.',
        ],
      ),
      LegalSection(
        heading: 'Where information comes from',
        bullets: <String>[
          'Information you enter or upload, including profile details, '
              'addresses, verification documents, livestock listings and '
              'photographs, messages, inquiries, offers and reports.',
          'Records created as you use the system, including account and '
              'verification status, listing visibility, transaction and '
              'fulfillment stages, read status, notifications and activity '
              'timestamps.',
          'Information returned by services you choose to use, such as the '
              'name and email from Google sign-in, a Firebase Cloud Messaging '
              'registration token for push notifications, and price-suggestion '
              'results from the configured prediction service.',
          'Profile, listing and seller-verification addresses are provided by '
              'users through the app’s address fields and location selector.',
        ],
      ),
      LegalSection(
        heading: 'Purposes and lawful basis',
        paragraphs: <String>[
          'Information supports account creation and security, seller review, '
              'listing display, buyer-seller communication, offers and transaction '
              'records, fulfillment updates, notifications, user reporting, '
              'moderation and optional price estimates. The operator must document '
              'the applicable RA 10173 lawful basis for each purpose before '
              'publication.',
          'Registration currently displays a Terms/Privacy checkbox that is '
              'checked locally by the app. The backend does not receive or retain '
              'a consent/acceptance record. The operator and counsel must confirm '
              'the appropriate notice and lawful-basis design; this draft does not '
              'treat the checkbox as a stored consent record.',
        ],
      ),
      LegalSection(
        heading: 'Who may receive information',
        paragraphs: <String>[
          'A public active listing displays seller-provided listing details, '
              'its location, and listing photos. Public seller summaries show '
              'limited profile information and a barangay-level location. Other '
              'users do not receive seller verification documents or private '
              'administrator review information.',
          'Conversation participants receive messages and relevant inquiry '
              'details. Transaction participants receive the other party’s name '
              'and email in the transaction resource. Authorized administrators '
              'review seller verification documents, reports and moderation '
              'records. Information may also be disclosed when required by law; '
              'the operator must confirm the applicable request-handling process.',
        ],
      ),
      LegalSection(
        heading: 'Service providers and external processing',
        paragraphs: <String>[
          'The app supports Google sign-in and Firebase Cloud Messaging for '
              'Android push delivery. Laravel sends livestock attributes to its '
              'configured FastAPI price-prediction service. Password reset uses a '
              'configured email service. Listing and verification storage can be '
              'configured for local or object storage.',
          'The precise providers, hosting locations, subprocessors, retention '
              'settings and any cross-border transfers have not been confirmed. '
              'The operator must publish the verified service-provider and '
              'transfer details before deployment.',
        ],
      ),
      LegalSection(
        heading: 'Security and access',
        paragraphs: <String>[
          'The backend uses authenticated mobile tokens and server-side '
              'authorization. Seller verification files and user-report evidence '
              'are stored on private disks and returned through authenticated '
              'routes; access is restricted by the relevant owner/administrator '
              'checks. Mobile bearer tokens are stored through the platform-secure '
              'storage integration on supported native devices.',
          'No encryption-at-rest method, independent security certification '
              'or complete security program has been confirmed for this policy. '
              'Those claims must not be added without verification.',
        ],
      ),
      LegalSection(
        heading: 'Retention, correction and deletion',
        paragraphs: <String>[
          'Profile information can be edited through the app. The system has '
              'no self-service account deletion or data-export feature. Administrator '
              'deactivation soft-deletes the account, revokes access and retains '
              'associated business history. Seller-verification records and their '
              'documents remain associated with submission history; the retention '
              'period and deletion rules for those documents are unresolved.',
          'No fixed retention period has been confirmed for messages, reports, '
              'device tokens, AI estimates, activity logs or other records. The '
              'operator must establish a retention schedule and explain how lawful '
              'retention needs interact with user requests before publication.',
        ],
      ),
      LegalSection(
        heading: 'Your privacy rights',
        paragraphs: <String>[
          'RA 10173 provides rights that may include being informed, access, '
              'correction, objecting or requesting blocking/erasure where the law '
              'allows, data portability where applicable, and lodging a complaint '
              'with the National Privacy Commission. The operator must confirm the '
              'request procedure, identity checks, response channel and any legal '
              'exceptions. The app does not currently provide a dedicated request '
              'workflow for all of these rights.',
          'Privacy contact: ${LegalMetadata.privacyContact}. Data protection '
              'contact: ${LegalMetadata.dataProtectionContact}. These details '
              'are placeholders pending operator confirmation and must be '
              'replaced before publication.',
        ],
      ),
      LegalSection(
        heading: 'Children and policy changes',
        paragraphs: <String>[
          'The application does not currently check a user’s age. The operator '
              'must decide and publish an age/minor policy before public release.',
          'The final policy must include its effective date, last-updated date '
              'and a user-facing notice process for material changes. Those dates '
              'are not yet approved.',
        ],
      ),
    ],
  );

  static const LegalDocument sellerPolicy = LegalDocument(
    id: 'seller-policy',
    title: 'Seller Policy',
    description: 'Seller approval, listing, offer and fulfillment duties.',
    icon: Icons.storefront_outlined,
    introduction:
        'This draft applies to AgroBenta users who use approved seller '
        'capabilities. It reflects the implemented verification, listing, '
        'offer and transaction workflows and requires operator/legal review.',
    sections: <LegalSection>[
      LegalSection(
        heading: 'Eligibility and verification',
        paragraphs: <String>[
          'Every account starts with buyer capability. A user who wants to '
              'sell submits seller-verification details and supporting documents. '
              'An administrator reviews the submission; only approval grants '
              'seller capability. An open submission must be decided before a new '
              'application can be made. A rejected application may be resubmitted '
              'as a new record.',
        ],
      ),
      LegalSection(
        heading: 'Verified Seller badge',
        paragraphs: <String>[
          'The badge indicates that the account currently has administrator-'
              'approved seller capability and is not deactivated. It is not a '
              'guarantee of livestock ownership, identity beyond the platform’s '
              'review, animal health, quality, seller statements, payment, delivery '
              'or transaction completion.',
        ],
      ),
      LegalSection(
        heading: 'Your listings and livestock',
        paragraphs: <String>[
          'Only an approved seller may create and manage their own listings. '
              'Currently supported new listing categories are Cattle, Carabao, '
              'Goat, Swine and Chicken. Provide accurate information about type, '
              'breed, age, sex, weight, price, available quantity, location, '
              'condition, vaccination and photographs as applicable.',
          'You must own the livestock or have lawful authority to offer it. '
              'Disclose material health or condition information and comply with '
              'applicable animal-welfare and transport laws. AgroBenta does not '
              'independently inspect animals or verify ownership, health or '
              'transport arrangements.',
        ],
      ),
      LegalSection(
        heading: 'Price and AI suggestions',
        paragraphs: <String>[
          'You set the asking price. The optional AI price suggestion is a '
              'reference for a seller’s draft listing, not a valuation, verified '
              'sale price or guarantee. It does not set or change your asking '
              'price. You remain responsible for the asking price you publish and '
              'for any price you agree in an offer.',
        ],
      ),
      LegalSection(
        heading: 'Photos, location and listing visibility',
        paragraphs: <String>[
          'A listing must include at least one stored photograph before it can '
              'be submitted for review. Photos on active listings are publicly '
              'accessible with the listing. Listing location is displayed to '
              'buyers; do not include personal details that are not necessary for '
              'the livestock listing. Use only photographs you may lawfully '
              'upload.',
          'New listings begin as drafts. Submitted listings are pending '
              'administrator review; only approved active listings are visible in '
              'the buyer marketplace. Sold and inactive listings are not available '
              'for new purchases. Fully reserved or unreconciled inventory may be '
              'hidden from buyers without the status changing immediately.',
        ],
      ),
      LegalSection(
        heading: 'Inquiries, offers and transactions',
        paragraphs: <String>[
          'Respond honestly and in a timely manner to genuine buyer inquiries. '
              'A seller offer is tied to an eligible inquiry and specifies its '
              'proposed amount and quantity and may include collection/payment '
              'terms. When the buyer accepts, the system creates a pending '
              'transaction and reserves the agreed stock. A direct buyer purchase '
              'can also create a pending transaction.',
          'Honor accepted transaction terms. Report preparation and the '
              'implemented pickup or delivery fulfillment steps accurately. '
              'Payment, livestock inspection, collection and transport are arranged '
              'directly between the buyer and seller; AgroBenta does not perform '
              'them.',
        ],
      ),
      LegalSection(
        heading: 'Inventory and cancellations',
        paragraphs: <String>[
          'Keep available quantity accurate. Pending transactions reserve '
              'stock atomically. A valid cancellation before seller dispatch or '
              'livestock handover releases the reservation exactly once. Do not '
              'promise that AgroBenta will accept cancellation after that cutoff; '
              'the app currently blocks it.',
        ],
      ),
      LegalSection(
        heading: 'Moderation and restrictions',
        paragraphs: <String>[
          'Administrators review submitted listings and seller verification. '
              'Listings may be rejected, deactivated or otherwise moderated under '
              'the implemented status workflow. Reports about user conduct may be '
              'reviewed by administrators. Account restriction details and any '
              'appeal process require operator/legal confirmation.',
        ],
      ),
    ],
  );

  static const LegalDocument buyerPolicy = LegalDocument(
    id: 'buyer-policy',
    title: 'Buyer Policy',
    description: 'Responsible inquiries, offers, purchases and collection.',
    icon: Icons.shopping_bag_outlined,
    introduction:
        'This draft explains the buyer-side actions currently available in '
        'AgroBenta. Buyers and sellers complete the livestock sale and make '
        'payment and collection arrangements directly with one another.',
    sections: <LegalSection>[
      LegalSection(
        heading: 'Use the marketplace responsibly',
        bullets: <String>[
          'Use accurate account details and contact sellers only for genuine '
              'livestock interest.',
          'Review listing details, seller information, availability, location '
              'and terms. Seller-provided age, weight, health and vaccination '
              'details are not independently verified by AgroBenta.',
          'Ask questions and arrange an inspection with the seller where '
              'appropriate before proceeding.',
          'Do not use inquiries or messages to spam, harass, impersonate or '
              'request fraudulent payments or credentials.',
        ],
      ),
      LegalSection(
        heading: 'Interest, inquiry, offer and transaction are different',
        paragraphs: <String>[
          'Opening a conversation or expressing interest does not itself create '
              'a transaction or reserve livestock. Submitting “I’m Interested” '
              'creates a structured inquiry and its opening message; it does not '
              'reserve stock.',
          'A seller may send an offer in response to an eligible inquiry. '
              'Accepting that offer creates a pending transaction and reserves the '
              'agreed quantity. The app also has a direct Buy / Inquire action that '
              'creates a pending transaction and reserves the selected quantity. '
              'A transaction record is separate from an inquiry or message.',
        ],
      ),
      LegalSection(
        heading: 'Price and payment',
        paragraphs: <String>[
          'Review the listed asking price per head and the quantity before '
              'buying. A direct purchase amount is calculated by the server from '
              'asking price and quantity; an accepted seller offer records its '
              'proposed total amount. Confirm the actual amount and terms with the '
              'seller.',
          'AgroBenta does not collect or process payment, hold money in escrow, '
              'verify payment, or issue a payment-status record. Payment method '
              'information is a preference/record only. Arrange payment directly '
              'and use your own judgment about payment safety.',
        ],
      ),
      LegalSection(
        heading: 'Collection, transport and animal welfare',
        paragraphs: <String>[
          'The inquiry and offer flows can record collection preferences such '
              'as personal pickup, buyer-arranged transportation, seller-arranged '
              'delivery or “not sure yet”. These choices do not book a carrier or '
              'make AgroBenta responsible for transport. Agree directly with the '
              'seller on location, timing, handling and lawful, humane transport.',
        ],
      ),
      LegalSection(
        heading: 'Cancellation and confirming receipt',
        paragraphs: <String>[
          'Either party may cancel a pending transaction before livestock '
              'handover or seller dispatch. The app blocks cancellation after that '
              'cutoff and has no refund or later dispute-resolution workflow. A '
              'valid cancellation releases the reserved quantity once.',
          'After the seller reports pickup or delivery handover, the buyer may '
              'confirm receipt in the app. This records the buyer’s confirmation; '
              'it is not independent proof of payment, livestock condition or '
              'delivery.',
        ],
      ),
      LegalSection(
        heading: 'Report suspected misconduct',
        paragraphs: <String>[
          'Use the in-app user-report action for suspected scam/fraud, '
              'harassment, misleading information, spam/suspicious activity, '
              'inappropriate content or another reportable concern. A report is '
              'sent for administrator review; it does not itself cancel a '
              'transaction, recover money or determine that a user violated a '
              'rule.',
        ],
      ),
    ],
  );

  static const LegalDocument livestockListingPolicy = LegalDocument(
    id: 'livestock-listing-policy',
    title: 'Livestock Listing Policy',
    description:
        'Listing information, visibility, stock and animal disclosures.',
    icon: Icons.pets_outlined,
    introduction:
        'This draft covers livestock listings created by approved sellers. The '
        'current backend catalog supports Cattle, Carabao, Goat, Swine and '
        'Chicken. Historical category values may remain visible in old records '
        'but are not supported for new listings.',
    sections: <LegalSection>[
      LegalSection(
        heading: 'Seller authority and allowed categories',
        paragraphs: <String>[
          'Only accounts with seller capability may create or manage their own '
              'livestock listings. List only animals you own or are legally '
              'authorized to offer. Supported new categories are Cattle, Carabao, '
              'Goat, Swine and Chicken; optional breeds come from the category '
              'catalog.',
        ],
      ),
      LegalSection(
        heading: 'Accurate listing information',
        paragraphs: <String>[
          'Provide accurate category and, where supplied, breed, age, sex, '
              'weight, asking price, available quantity, condition, vaccination '
              'details, description and Trinidad location. Do not describe an '
              'estimate as a measured fact. Clearly distinguish seller estimates '
              'from measured information where the form asks.',
          'Disclose known health, condition or other material facts that a '
              'buyer needs to make an informed decision. Listing health and '
              'vaccination fields are seller-provided and are not veterinary '
              'certifications issued by AgroBenta.',
        ],
      ),
      LegalSection(
        heading: 'Photographs and content',
        paragraphs: <String>[
          'At least one stored photograph is required before submission for '
              'review. Submitted photographs should truthfully represent the '
              'livestock offered and must not be misleading or used without '
              'permission. Photographs on an active listing are accessible to '
              'marketplace users.',
        ],
      ),
      LegalSection(
        heading: 'Price and price suggestions',
        paragraphs: <String>[
          'The seller chooses the final asking price, which is displayed per '
              'head. The optional AI suggestion is available for an eligible '
              'seller’s draft and does not automatically set or replace the price. '
              'See the AI Price Suggestion Disclaimer for its limitations.',
        ],
      ),
      LegalSection(
        heading: 'Quantity and reservations',
        paragraphs: <String>[
          'Enter the quantity actually available. A pending direct transaction '
              'or accepted offer reserves the agreed quantity. Available stock '
              'may therefore decrease while a listing remains active. Fully '
              'reserved, sold-out or unreconciled inventory may be hidden from new '
              'buyer activity. Do not promise reserved stock to another buyer.',
        ],
      ),
      LegalSection(
        heading: 'Status, visibility and moderation',
        paragraphs: <String>[
          'A new listing is a private draft. Submitting it changes it to '
              'pending for administrator review. Only an approved active listing '
              'is shown in the buyer marketplace. Sold and inactive listings are '
              'not offered for new marketplace transactions. Sellers do not set '
              'the status directly.',
          'Administrators may review, approve, reject or deactivate listings '
              'under the implemented moderation workflow. A listing can be hidden '
              'when the seller account is deactivated or its inventory is not '
              'available, without a public listing page being shown.',
        ],
      ),
      LegalSection(
        heading: 'Animal welfare and collection',
        paragraphs: <String>[
          'Sellers remain responsible for appropriate care and for complying '
              'with applicable animal-welfare requirements, including the Animal '
              'Welfare Act of 1998 (RA 8485) as amended by RA 10631. Buyers and '
              'sellers arrange lawful, humane handling and transport directly. '
              'AgroBenta does not inspect or transport animals and does not '
              'certify compliance with those laws.',
        ],
      ),
      LegalSection(
        heading: 'Prohibited listing content',
        paragraphs: <String>[
          'Do not list livestock you cannot lawfully sell, unavailable or '
              'misrepresented animals, false quantities, deceptive prices, '
              'unauthorized photographs, or content that violates applicable law '
              'or the Community and Messaging Policy. Reports and administrator '
              'review are available for suspected violations.',
        ],
      ),
    ],
  );

  static const LegalDocument transactionAndCancellationPolicy = LegalDocument(
    id: 'transaction-and-cancellation-policy',
    title: 'Transaction and Cancellation Policy',
    description: 'How offers, reservations, fulfillment and cancellation work.',
    icon: Icons.receipt_long_outlined,
    introduction:
        'AgroBenta records a buyer-seller livestock transaction and its '
        'progress. Buyers and sellers make payment, inspection and collection '
        'arrangements directly. The transaction record is not proof of '
        'payment or delivery.',
    sections: <LegalSection>[
      LegalSection(
        heading: 'Interest and inquiry',
        paragraphs: <String>[
          'A conversation or expression of interest is not a transaction and '
              'does not reserve stock. Submitting an inquiry records the buyer’s '
              'interest, requested quantity and available preferences and opens '
              'the conversation with the seller. It does not itself change '
              'inventory.',
        ],
      ),
      LegalSection(
        heading: 'Seller offers and buyer acceptance',
        paragraphs: <String>[
          'A seller may send an offer tied to an eligible buyer inquiry. The '
              'offer records a proposed total amount, quantity and any included '
              'payment or collection preferences. The buyer may accept, decline or '
              'communicate with the seller. Acceptance creates a pending '
              'transaction for the agreed amount and quantity and reserves that '
              'quantity.',
        ],
      ),
      LegalSection(
        heading: 'Direct purchase and transaction creation',
        paragraphs: <String>[
          'The mobile app also provides a direct Buy / Inquire action. Choosing '
              'a quantity there creates a pending transaction against an active '
              'listing; the server calculates the direct-purchase total from the '
              'current asking price per head and quantity and reserves stock. A '
              'client cannot set the total amount.',
          'An accepted offer instead records the offer’s proposed total. '
              'Review the quantity and total shown by the server before '
              'proceeding.',
        ],
      ),
      LegalSection(
        heading: 'Payment and collection arrangements',
        paragraphs: <String>[
          'AgroBenta does not accept, process, hold or refund payments. Payment '
              'method data is a preference/record, not evidence that payment was '
              'made. The app does not provide, book or track transportation. '
              'Buyers and sellers agree directly on payment, inspection, pickup or '
              'seller-arranged delivery and any related arrangements.',
        ],
      ),
      LegalSection(
        heading: 'Fulfillment and transaction progress',
        paragraphs: <String>[
          'The transaction begins as pending. Sellers may report preparation '
              'and the applicable pickup or delivery stages. Pickup progresses '
              'through ready for pickup and picked up; seller-arranged delivery '
              'uses on-the-way and delivered. These are user-reported workflow '
              'stages; AgroBenta does not independently verify physical events.',
          'After handover is recorded, the buyer may confirm receipt. The '
              'transaction then becomes completed and a receipt snapshot is '
              'available to the parties. The receipt records transaction details '
              'and is not proof of payment.',
        ],
      ),
      LegalSection(
        heading: 'Cancellation eligibility',
        paragraphs: <String>[
          'Either buyer or seller may cancel a pending transaction before '
              'livestock handover or seller dispatch. The app blocks cancellation '
              'after pickup handover or seller dispatch. The app does not provide '
              'a later cancellation, refund, mediation or dispute-resolution '
              'workflow.',
          'When an eligible transaction reserved stock, cancellation releases '
              'that quantity once. Historical transactions that did not reserve '
              'stock do not cause inventory to be added back.',
        ],
      ),
      LegalSection(
        heading: 'Disputes, remedies and legal rights',
        paragraphs: <String>[
          'The current mobile system has no transaction dispute state, refund '
              'mechanism or in-app mediation process. User reporting addresses '
              'suspected misconduct and does not settle a sale dispute. Nothing in '
              'this draft removes rights that may exist under applicable law. '
              'The operator must approve the final remedies and complaint '
              'information.',
        ],
      ),
    ],
  );

  static const LegalDocument communityAndMessagingPolicy = LegalDocument(
    id: 'community-and-messaging-policy',
    title: 'Community and Messaging Policy',
    description: 'Expected conduct, messaging, reporting and moderation.',
    icon: Icons.forum_outlined,
    introduction:
        'AgroBenta messaging supports buyer-seller conversations, inquiries, '
        'offers and transaction-related communication. Treat other users '
        'respectfully and keep messages relevant to legitimate marketplace '
        'activity.',
    sections: <LegalSection>[
      LegalSection(
        heading: 'Respectful communication',
        bullets: <String>[
          'Communicate truthfully and respectfully, even when you disagree.',
          'Do not harass, threaten, intimidate, discriminate against or '
              'repeatedly contact a person after they ask you to stop.',
          'Do not send spam, unsolicited promotions, suspicious links or '
              'repeated irrelevant messages.',
          'Do not impersonate another person or misrepresent a listing, '
              'payment request, offer, animal or transaction.',
          'Do not request passwords, one-time codes, access tokens or other '
              'authentication secrets. Do not disclose another person’s '
              'private information without authority.',
        ],
      ),
      LegalSection(
        heading: 'Payment and transaction messages',
        paragraphs: <String>[
          'AgroBenta does not process payment or act as escrow. Be cautious '
              'about payment instructions and verify arrangements directly with '
              'the other party. A message, payment preference or notification '
              'does not prove that money was transferred.',
          'Seller offers are made through the offer workflow when available. '
              'Do not claim a message alone changed a transaction or reserved '
              'livestock; transaction creation and inventory reservation are '
              'recorded separately by the system.',
        ],
      ),
      LegalSection(
        heading: 'How messaging works',
        paragraphs: <String>[
          'Messages are associated with the signed-in account and available '
              'to the conversation participants. Read status may be shown to the '
              'other participant. The app applies sending limits to reduce spam.',
          'A conversation may remain available to its participants after a '
              'listing is sold, inactive or no longer visible to buyers when an '
              'established inquiry or transaction relates to that exact '
              'conversation and listing. This does not reopen the listing for sale.',
          'When you attach a listing to a message, it must be visible to you '
              'or connected to an established inquiry or transaction in that '
              'conversation. A hidden or unrelated listing cannot be added simply '
              'by supplying its identifier.',
          'Chat messages are not delivered as phone push notifications in the '
              'current implementation. Stored system notifications may be pushed '
              'to an Android device registered to the signed-in session.',
        ],
      ),
      LegalSection(
        heading: 'Reporting and review',
        paragraphs: <String>[
          'You can report a user for scam/fraud, harassment, misleading '
              'information, spam/suspicious activity, inappropriate content or '
              'another concern. A description is required; one optional image may '
              'be submitted as evidence. Reports and optional evidence are '
              'available to authorized administrators for review.',
          'A report does not automatically establish a violation, deactivate '
              'an account or cancel a transaction. Administrators review reports '
              'and may take account action under the platform’s moderation '
              'workflow. The operator must confirm any response or appeal process '
              'before publishing it.',
        ],
      ),
    ],
  );

  static const LegalDocument aiPriceSuggestionDisclaimer = LegalDocument(
    id: 'ai-price-suggestion-disclaimer',
    title: 'AI Price Suggestion Disclaimer',
    description:
        'What an automated livestock price estimate can and cannot say.',
    icon: Icons.insights_outlined,
    introduction:
        'AgroBenta’s price suggestion is automated decision-support for '
        'sellers preparing a draft listing. In the current mobile application, '
        'buyers do not receive a separate AI estimate on marketplace listing '
        'details; buyers see the seller’s asking price.',
    sections: <LegalSection>[
      LegalSection(
        heading: 'Purpose',
        paragraphs: <String>[
          'The service returns an estimated point price to help an approved '
              'seller consider an asking price for a draft livestock listing. It '
              'is optional and does not automatically set or change the asking '
              'price.',
        ],
      ),
      LegalSection(
        heading: 'Information considered',
        paragraphs: <String>[
          'The current prediction request uses livestock category, breed, '
              'sex, age and weight (with age and weight converted to the service’s '
              'expected units). The backend stores the submitted input snapshot, '
              'estimate, status, basis and prediction-service metadata with the '
              'listing’s estimate history. The current request does not include '
              'listing location or health/vaccination fields.',
        ],
      ),
      LegalSection(
        heading: 'Limitations and possible errors',
        paragraphs: <String>[
          'An estimate is not a professional appraisal, a verified market '
              'price, a sale record, a government price, a buyer offer or a '
              'guarantee that livestock will sell at that amount. It can be '
              'inaccurate or unavailable because listing information, model '
              'coverage, regional conditions and animal-specific factors may not '
              'be fully represented.',
          'The current response is a point estimate with a status and '
              'provider-supplied basis or warning; the service may withhold a '
              'result. AgroBenta has not confirmed that the estimate uses live '
              'market prices, verified real-world sales or government pricing '
              'data. Data provenance and coverage must be confirmed by the '
              'operator before publication.',
        ],
      ),
      LegalSection(
        heading: 'Seller and buyer decisions',
        paragraphs: <String>[
          'The seller alone chooses the final asking price and is responsible '
              'for the price published. Buyers should assess the seller’s asking '
              'price and livestock information independently. The buyer and '
              'seller are responsible for the amount and quantity they agree to '
              'in a direct purchase or accepted offer; the backend records the '
              'applicable total for that transaction.',
        ],
      ),
      LegalSection(
        heading: 'Factors outside the estimate',
        paragraphs: <String>[
          'Livestock value may depend on health, condition, breed, age, sex, '
              'weight, location, season, buyer demand, transport costs, inspection '
              'and other circumstances. The suggestion may not include all of '
              'these factors and does not replace buyer inspection or seller '
              'judgment.',
        ],
      ),
      LegalSection(
        heading: 'Service provider and policy review',
        paragraphs: <String>[
          'Laravel currently communicates with a configured FastAPI '
              'prediction service. The accountable operator, dataset provenance, '
              'training and evaluation details, service-provider terms and '
              'retention practices must be confirmed before public deployment. '
              'This document does not claim that AgroBenta independently trained '
              'the model or that any estimate is guaranteed.',
        ],
      ),
    ],
  );
}
