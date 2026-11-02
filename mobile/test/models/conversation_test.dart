import 'package:agrobenta_mobile/models/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/messaging_fakes.dart';

void main() {
  group('Conversation.fromJson', () {
    test('reads roles, listing count and previews from ConversationResource', () {
      final Conversation conversation = Conversation.fromJson(
        conversationJson(
          roles: const <String>['buyer'],
          listingCount: 2,
          latestOffer: conversationOfferJson(
            status: 'pending',
            proposedAmount: '47500.00',
          ),
          eligibleInquiry: eligibleInquiryJson(id: 55, listingId: 12),
        ),
      );

      expect(conversation.roles, <String>['buyer']);
      expect(conversation.listingCount, 2);
      expect(conversation.latestOffer?.status.value, 'pending');
      expect(conversation.latestOffer?.proposedAmount, '47500.00');
      expect(conversation.latestOffer?.isPending, isTrue);
      expect(conversation.eligibleInquiry?.id, 55);
      expect(conversation.eligibleInquiry?.listingId, 12);
    });

    test('missing preview fields stay absent rather than throwing', () {
      final Map<String, dynamic> json = conversationJson()
        ..remove('roles')
        ..remove('listing_count')
        ..remove('latest_offer')
        ..remove('eligible_inquiry');

      final Conversation conversation = Conversation.fromJson(json);

      expect(conversation.roles, isEmpty);
      expect(conversation.listingCount, 0);
      expect(conversation.latestOffer, isNull);
      expect(conversation.eligibleInquiry, isNull);
    });

    test('an unknown offer status degrades to no preview, not a crash', () {
      final Conversation conversation = Conversation.fromJson(
        conversationJson(
          latestOffer: conversationOfferJson(status: 'something-new'),
        ),
      );

      expect(conversation.latestOffer, isNull);
      // The rest of the conversation still loads.
      expect(conversation.counterpart.name, isNotNull);
    });
  });

  group('matchesMode', () {    Conversation conversationWith(List<String> roles) =>
        Conversation.fromJson(conversationJson(roles: roles));

    test('buyer-side only appears in Buyer Mode', () {
      final Conversation c = conversationWith(<String>['buyer']);
      expect(c.matchesMode(sellerMode: false), isTrue);
      expect(c.matchesMode(sellerMode: true), isFalse);
    });

    test('seller-side only appears in Seller Mode', () {
      final Conversation c = conversationWith(<String>['seller']);
      expect(c.matchesMode(sellerMode: false), isFalse);
      expect(c.matchesMode(sellerMode: true), isTrue);
    });

    test('a pair traded both ways appears in both modes', () {
      final Conversation c = conversationWith(<String>['buyer', 'seller']);
      expect(c.matchesMode(sellerMode: false), isTrue);
      expect(c.matchesMode(sellerMode: true), isTrue);
    });

    test('an unclassified thread is never hidden', () {
      final Conversation c = conversationWith(const <String>[]);
      expect(c.isUnclassified, isTrue);
      expect(c.matchesMode(sellerMode: false), isTrue);
      expect(c.matchesMode(sellerMode: true), isTrue);
    });
  });

  test('copyWith keeps the preview fields when clearing unread', () {
    final Conversation original = Conversation.fromJson(
      conversationJson(
        roles: const <String>['seller'],
        listingCount: 3,
        latestOffer: conversationOfferJson(),
        eligibleInquiry: eligibleInquiryJson(),
        unreadCount: 4,
      ),
    );

    final Conversation read = original.copyWith(unreadCount: 0);

    expect(read.unreadCount, 0);
    expect(read.roles, original.roles);
    expect(read.listingCount, 3);
    expect(read.latestOffer?.id, original.latestOffer?.id);
    expect(read.eligibleInquiry?.id, original.eligibleInquiry?.id);
  });

  group('counterpartRole', () {
    Conversation withRoles(List<String> roles) =>
        Conversation.fromJson(conversationJson(roles: roles));

    test('a buyer-side thread names the counterpart a Seller', () {
      expect(withRoles(<String>['buyer']).counterpartRole, 'Seller');
    });

    test('a seller-side thread names the counterpart a Buyer', () {
      expect(withRoles(<String>['seller']).counterpartRole, 'Buyer');
    });

    test('both sides and unclassified threads do not guess', () {
      expect(withRoles(<String>['buyer', 'seller']).counterpartRole, isNull);
      expect(withRoles(const <String>[]).counterpartRole, isNull);
    });
  });

  test('the eligible inquiry carries the listing photo for the offer form', () {
    final Conversation conversation = Conversation.fromJson(
      conversationJson(
        eligibleInquiry: eligibleInquiryJson(
          listingPhotoUrl: 'https://files.test/heifer.jpg',
        ),
      ),
    );

    expect(
      conversation.eligibleInquiry?.photoUrl,
      'https://files.test/heifer.jpg',
    );
  });
}
