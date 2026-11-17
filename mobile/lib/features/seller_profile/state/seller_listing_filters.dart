/// The documented ordering for one seller's public listing page.
///
/// The `value` is the exact string `IndexSellerPublicListingRequest` validates
/// and `MarketplaceListingRepository` applies in SQL. The label is what the
/// sort control shows.
enum SellerListingSort {
  newest('newest', 'Newest first'),
  oldest('oldest', 'Oldest first'),
  priceLowToHigh('price_asc', 'Price: Low to High'),
  priceHighToLow('price_desc', 'Price: High to Low');

  const SellerListingSort(this.value, this.label);

  final String value;
  final String label;

  /// Parses a server value, falling back to newest for anything unrecognised.
  static SellerListingSort fromValue(String value) {
    for (final SellerListingSort sort in SellerListingSort.values) {
      if (sort.value == value) {
        return sort;
      }
    }
    return SellerListingSort.newest;
  }
}
