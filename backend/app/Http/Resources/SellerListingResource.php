<?php

namespace App\Http\Resources;

use App\Models\Listing;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** Seller-owned listing projection with explicitly supplied action hints. */
class SellerListingResource extends JsonResource
{
    /**
     * @param  array{seller_can_reactivate: bool, seller_can_delete: bool}  $actionHints
     */
    public function __construct(Listing $resource, private readonly array $actionHints)
    {
        parent::__construct($resource);
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $data = (new MobileListingResource($this->resource))->toArray($request);

        if ($request->user() !== null && (int) $request->user()->getKey() === (int) $this->seller_id) {
            $data['seller_can_reactivate'] = $this->actionHints['seller_can_reactivate'];
            $data['seller_can_delete'] = $this->actionHints['seller_can_delete'];
        }

        return $data;
    }
}
