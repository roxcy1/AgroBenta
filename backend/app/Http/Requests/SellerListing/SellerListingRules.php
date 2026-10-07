<?php

namespace App\Http\Requests\SellerListing;

use App\Enums\ListingStatus;

/**
 * The field rules for seller listing creation and update.
 *
 * Contract §5.4 specifies the create rules once and then says update uses "as
 * §5.4, but every field `sometimes`". Implementing that as a second, separately
 * written rule set is how the two drift: a rule tightened here and forgotten
 * there means a field the seller cannot set on create can be set on update.
 * This trait is that single definition, and the request classes differ only in
 * how required they are and in which rules apply to client input.
 *
 * The allow-list is the allow-list: everything in [contentRules()] is
 * something a seller may set, and the request classes add
 * [ownershipRules()] to reject everything else — `status` and `seller_id` above
 * all. A denylist would fail open when a column is added to the model later
 * (functional documentation §10.1, contract §4.5.2).
 */
trait SellerListingRules
{
    /**
     * The writable content fields, with no required/sometimes decision.
     *
     * @return array<string, list<string>>
     */
    protected function contentRules(): array
    {
        return [
            'livestock_type' => ['string', 'max:255'],

            // `breed` and `short_description` are NOT NULL columns with no
            // database default, so they are optional at the API boundary but
            // cannot be absent at the storage layer. The service supplies an
            // empty string for an absent value; requiring a breed here instead
            // would invent a business rule the documentation does not have
            // (functional documentation §4.1 treats it as free text, not a
            // controlled field).
            'breed' => ['nullable', 'string', 'max:255'],

            // `age_value` is validated as an integer per the contract even though
            // the column is `decimal(5,1)`: the contract is authoritative for what
            // a client may send, and a looser column is not a licence to send
            // fractions.
            'age_value' => ['integer', 'min:0'],
            'age_unit' => ['in:day,month,year'],

            'gender' => ['in:male,female'],

            // Bounded to the column's own range (`decimal(10,2)`) so an
            // out-of-range weight is a 422 with a readable message rather than a
            // database error the seller cannot act on.
            'weight_value' => ['numeric', 'min:0', 'max:99999999.99'],
            'weight_unit' => ['in:kg,lb'],

            'quantity' => ['integer', 'min:1'],

            // `numeric`, not `decimal`, and bounded to `decimal(14,2)`, for the
            // same reason. Precision is not truncated to two places here: the
            // column does that, and rounding a seller's price in the request
            // layer would hide the behaviour from the test that should catch it.
            'asking_price' => ['numeric', 'min:0', 'max:99999999999.99'],

            'location' => ['string', 'max:255'],
            'health_status' => ['nullable', 'string', 'max:255'],
            'vaccination' => ['nullable', 'string', 'max:255'],
            'short_description' => ['nullable', 'string', 'max:255'],
            'additional_notes' => ['nullable', 'string', 'max:2000'],

            // A JSON column of stored values, exposed by the mobile API because
            // the marketplace must be able to show them (contract §8.2). How a
            // photo is *added* is still undecided — D-10 leaves the upload
            // mechanism and URL scheme open — so this endpoint accepts whatever
            // strings it is given and never invents one. The mobile client sends
            // no `photos` at all until D-10 is answered.
            'photos' => ['array'],
            'photos.*' => ['string'],
        ];
    }

    /**
     * The four fields a listing cannot be created without.
     *
     * @return array<string, list<string>>
     */
    protected function requiredFieldRules(): array
    {
        return [
            'livestock_type' => ['string', 'max:255'],
            'location' => ['string', 'max:255'],
            'asking_price' => ['numeric', 'min:0', 'max:99999999999.99'],
            'quantity' => ['integer', 'min:1'],
        ];
    }

    /**
     * The rules for the two value/unit pairs, which are meaningless apart.
     *
     * `age_value` without `age_unit` (or the reverse) is not a listing anybody
     * can read, so the contract requires both together (§5.4). Applied on create
     * and on submit, because a half pair is not something to store.
     *
     * @return array<string, list<string>>
     */
    protected function pairRules(): array
    {
        return [
            'age_value' => ['required_with:age_unit'],
            'age_unit' => ['required_with:age_value'],
            'weight_value' => ['required_with:weight_unit'],
            'weight_unit' => ['required_with:weight_value'],
        ];
    }

    /**
     * The rules a listing must satisfy to be *storable*, ignoring where the
     * values came from.
     *
     * Used for create, for update, and again for submit — because the contract
     * requires a listing to satisfy the create rules at the moment it is
     * submitted (§5.4), and a draft written before those rules tightened, or
     * created outside this API, has to be checked at that point rather than
     * trusted.
     *
     * Deliberately excludes [ownershipRules()]: the stored listing of course has
     * a `status` and a `seller_id`, and validating those against the
     * client-input rules would reject every existing row.
     *
     * @return array<string, list<string>>
     */
    public function submissionRules(): array
    {
        return $this->mergeRules(
            $this->contentRules(),
            $this->pairRules(),
            $this->requiredFieldRules(),
        );
    }

    /**
     * Combine rule sets, appending rules for a field that appears in more than
     * one of them.
     *
     * `array_merge` is the wrong tool here and fails quietly: with string keys a
     * later value *replaces* an earlier one, so `pairRules()` handing out
     * `age_value => ['required_with:age_unit']` would silently delete
     * `['integer', 'min:0']` from `contentRules()`. The result is a request that
     * looks correct and accepts a fractional age.
     *
     * Appended rather than replaced, and de-duplicated while preserving order, so
     * each rule set stays readable on its own and the combination is the union of
     * what they all say.
     *
     * @param  array<string, list<string>>  ...$sets
     * @return array<string, list<string>>
     */
    protected function mergeRules(array ...$sets): array
    {
        $merged = [];

        foreach ($sets as $set) {
            foreach ($set as $field => $rules) {
                $merged[$field] = array_values(array_unique([
                    ...($merged[$field] ?? []),
                    ...$rules,
                ]));
            }
        }

        return $merged;
    }

    /**
     * The fields a client may not choose.
     *
     * Rejected with a 422 rather than ignored: dropping them silently would hide
     * a client bug, and honouring them would let a seller self-publish (`status`)
     * or write to another seller's row (`seller_id`).
     *
     * `admin_note` is here because the column exists and is mass-assignable on
     * the model, which is exactly the case this list exists for: it was added for
     * administrator rejection, and adding a fillable column without adding it
     * here would make it settable by any seller who guessed the name. It is
     * server-written only, from the admin moderation action.
     *
     * @return array<string, list<string>>
     */
    protected function ownershipRules(): array
    {
        return [
            'status' => ['prohibited'],
            'seller_id' => ['prohibited'],
            'admin_note' => ['prohibited'],
        ];
    }

    /**
     * The status values a seller may filter their own list by.
     *
     * All five, unlike the marketplace, where the status is not a parameter at
     * all (contract §5.2). A seller sees their own work in every state; that is
     * the whole point of the screen.
     *
     * @return list<string>
     */
    protected static function ownStatusValues(): array
    {
        return array_map(
            static fn (ListingStatus $status): string => $status->value,
            ListingStatus::cases(),
        );
    }
}
