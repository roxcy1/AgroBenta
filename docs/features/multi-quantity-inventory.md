# Multi-quantity listings and partial sales

**Decision:** DEC-10, approved by the project manager on 2026-11-14. It
supersedes DEC-09's one-head-per-offer limit. The matching business-rule entry
is in `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md` §§4.4, 6.1, 6.4 and 13.8.

## Business rules

- A listing may represent multiple similar animals with one shared per-head
  asking price. Its total quantity is distinct from its currently available
  quantity.
- A buyer requests a positive whole-number quantity. A seller offer must cover
  at least one and no more than the buyer requested; the seller may offer fewer.
- An offer's `proposed_amount` remains the total agreed amount for
  `proposed_quantity`. Accepting the offer creates one transaction for that
  quantity and preserves the amount without recalculating it from the listing's
  asking price.
- Reservations are atomic. Concurrent acceptance cannot reserve more than the
  verified available quantity. Cancellation restores reserved stock exactly
  once; completion accounts the reservation as an AgroBenta sale.
- Seller Mark Sold accounts all remaining available quantity as sold outside
  AgroBenta and is refused while inventory is reserved. Unavailable or fully
  reserved stock is excluded from new Marketplace activity.
- Historical transactions with `inventory_reserved = false` are not evidence
  that a quantity was reserved or sold. They do not create inferred sales or
  cancellation restoration.

## Inventory representation

`listings.quantity` remains the compatibility field and means available stock.
The inventory ledger also exposes total quantity, currently reserved quantity,
AgroBenta-completed sales, external sales, combined sold quantity, and an
inventory-reconciliation flag. A verified listing maintains:

```text
available = total - reserved - platform_sold - externally_sold
```

Mobile listing resources expose the inventory fields additively. Inquiry and
offer resources expose `requested_quantity` and `proposed_quantity`; transaction
resources already carry `quantity` and `total_amount`.

## Legacy inventory handling

The additive migration uses the prior available quantity plus quantities from
pending/completed transactions explicitly marked `inventory_reserved = true`.
Unreserved pending/completed rows make transaction allocation uncertain; the
listing is flagged and its original `listings.quantity` is retained as a
snapshot rather than presented as verified stock. The migration does not edit
transaction history. An administrator must reconcile physical stock,
externally-sold quantity, transaction allocations, reason, and evidence before
the listing can return to Marketplace activity.

Before implementation, a read-only audit of the local database found eight
active listings with transaction history whose reservations were all false;
four of those had transaction totals exceeding the stored quantity. The
backfill intentionally quarantines ambiguous transaction-bearing listings
rather than limiting quarantine to only the four visibly overcommitted rows.
The local application database migration was not run.

## API and client behavior

- Seller listing create/update uses `total_quantity`; the API keeps `quantity`
  as the available-stock response field.
- Inquiry create includes `requested_quantity`.
- Offer create includes `proposed_quantity` and total `proposed_amount`.
- Direct transaction create includes `quantity`, and acceptance of an offer
  copies its agreed quantity and total amount.
- Admin Web lists inventory status and supports a reason/evidence-backed
  reconciliation action. Mobile is not given administrator routes or screens.
- Inventory updates are broadcast after commit; Flutter refreshes Marketplace
  data and Admin Web invalidates listing queries.

## Validation status

- Backend `composer test` on the synchronized `origin/main` base: **951 passed**,
  1 skipped (4,397 assertions).
  Inventory backfill/reconciliation, end-to-end multi-quantity lifecycle, offer,
  transaction, and Marketplace tests passed.
- The added migration integration test exercised both real feature migrations
  over synthetic pre-feature listings, reservations, ambiguous transactions,
  and legacy inquiry/offer rows on SQLite; it verified preservation and safe
  defaults without touching application data.
- The opt-in MySQL concurrency test passed on the isolated
  `agrobenta_multi_quantity_test` database (1 test, 6 assertions). Migrations
  were applied only to that test database; the local application database was
  not changed.
- Flutter `flutter analyze`: **clean**. Full `flutter test`: **1,174 passed**,
  1 skipped. The debug APK built and launched to `MainActivity` on the
  `Medium Phone API 36.1` emulator. The Android flow was smoke-tested only; the
  full buyer/seller workflow was not manually exercised on-device.
- Admin Web typecheck, lint, tests (**268 passed**) and production build passed.
