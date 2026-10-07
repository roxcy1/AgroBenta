<?php

namespace App\Http\Requests\SellerListing;

/**
 * Body for editing a listing.
 *
 * "As §5.4, but every field `sometimes`" (contract §5.4) is implemented as the
 * same [SellerListingRules] with `sometimes` added to every field, rather than as
 * a second hand-written rule array. The two requests then cannot drift: a rule
 * tightened on create is tightened on update in the same commit.
 *
 * `sometimes` is the right tool here because this is a genuine PATCH: absent
 * means "leave it alone", not "clear it". Note the consequence, which is a
 * storage constraint rather than a validation one — a field that is `NOT NULL`
 * with no default cannot be *unset* by omission, only given a new value.
 */
class UpdateSellerListingRequest extends StoreSellerListingRequest
{
    /**
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        $rules = parent::rules();

        foreach ($rules as $field => $fieldRules) {
            $rewritten = array_values(array_filter(
                $fieldRules,
                // `required` is dropped: on a PATCH it would turn the *presence*
                // of unrelated fields into a precondition. Left in place, sending
                // only `breed` would demand the four create-time required fields,
                // and a seller correcting one typo would get a page of errors
                // about fields they never touched.
                //
                // `required_with` goes with it, and this is deliberate rather than
                // an oversight: `sometimes` disables it, because Laravel skips a
                // field that is absent, so the pair rule could not fire on a
                // partial update even if it were kept. Rewriting it to
                // `prohibited_without` does not rescue it — that rule is not
                // evaluated for an absent partner field.
                //
                // The pair invariant is therefore enforced where the contract
                // says it matters: a listing must satisfy the create rules at the
                // moment it is submitted, and
                // [SellerListingService::submit()] re-checks them, so a half pair
                // cannot reach a moderator. A seller may therefore leave a
                // listing with an incomplete pair, and the consequence is that
                // they cannot submit it yet — which is the documented rule rather
                // than a new one.
                static fn (string $rule): bool => ! str_starts_with($rule, 'required'),
            ));

            $rewritten[] = 'sometimes';
            $rules[$field] = $rewritten;
        }

        return $rules;
    }
}
