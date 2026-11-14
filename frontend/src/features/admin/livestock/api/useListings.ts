import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import api from '../../../../lib/api';
import type { ListingStatus, ModerationAction } from '../components/listingModeration';

export interface ListingSeller {
  id: number;
  name: string;
  email: string;
}

export interface Listing {
  id: number;
  seller: ListingSeller;
  livestock_type: string;
  breed: string;
  age_value: number | null;
  age_unit: string | null;
  gender: string | null;
  weight_value: number | null;
  weight_unit: string | null;
  quantity: number;
  total_quantity: number | null;
  reserved_quantity: number | null;
  platform_sold_quantity: number | null;
  sold_quantity: number | null;
  available_quantity: number | null;
  externally_sold_quantity: number | null;
  inventory_reconciliation_required: boolean;
  legacy_quantity_snapshot: number | null;
  unaccounted_inventory_transactions?: Array<{
    id: number;
    status: 'pending' | 'completed';
    quantity: number;
  }>;
  latest_inventory_reconciliation?: {
    id: number;
    admin: { id: number; name: string } | null;
    verified_physical_quantity: number;
    verified_pending_quantity: number;
    verified_completed_quantity: number;
    verified_externally_sold_quantity: number;
    verified_total_quantity: number;
    verified_available_quantity: number;
    reason: string;
    evidence: string | null;
    created_at: string | null;
  } | null;
  asking_price: string;
  location: string;
  health_status: string | null;
  vaccination: string | null;
  short_description: string;
  additional_notes: string | null;
  /** Absolute, fetchable photo URLs in stored order. Empty when there are none. */
  photos: string[];
  status: ListingStatus;
  /** Administrator-only. Never present on the mobile listing resource. */
  admin_note: string | null;
  created_at: string;
  updated_at: string;
}

export interface ListingsPagination {
  current_page: number;
  last_page: number;
  per_page: number;
  total: number;
}

export interface ListingsData {
  listings: Listing[];
  pagination: ListingsPagination;
}

interface ListingsResponse {
  success: boolean;
  data: ListingsData;
}

interface ModerationResponse {
  success: boolean;
  message: string;
  data: Listing;
}

export interface ListingsParams {
  search?: string;
  livestock_type?: string;
  status?: string;
  page?: number;
  per_page?: number;
}

async function fetchListings(params: ListingsParams): Promise<ListingsData> {
  const query = new URLSearchParams();
  if (params.search) query.set('search', params.search);
  if (params.livestock_type) query.set('livestock_type', params.livestock_type);
  if (params.status) query.set('status', params.status);
  if (params.page) query.set('page', String(params.page));
  if (params.per_page) query.set('per_page', String(params.per_page));

  const qs = query.toString();
  const url = `/admin/listings${qs ? `?${qs}` : ''}`;

  const response = await api.get<ListingsResponse>(url);
  return response.data.data;
}

/**
 * Call one of the three named moderation actions.
 *
 * These are actions, not a status setter: the endpoint decides the resulting
 * status and the body never carries one, so there is no request this function
 * can build that would move a listing somewhere the contract has not put it.
 * `admin_note` is sent for rejection only, because that is the one action the
 * contract annotates with a note.
 */
async function moderate(
  action: ModerationAction,
  id: number,
  adminNote?: string,
): Promise<ModerationResponse> {
  const body = action === 'reject' && adminNote ? { admin_note: adminNote } : {};

  const response = await api.post<ModerationResponse>(`/admin/listings/${id}/${action}`, body);
  return response.data;
}

/**
 * Invalidate every listing view after a decision.
 *
 * The list key is the prefix, so this clears the current page *and* the filtered
 * ones. That matters for the stale-decision case: a 409 means the server's row
 * has moved on since the table was rendered, and the only correct response is
 * to re-read it, not to leave a row on screen that the server has already
 * changed.
 */
function useInvalidateListings() {
  const queryClient = useQueryClient();

  return () => {
    void queryClient.invalidateQueries({ queryKey: ['admin', 'listings'] });
  };
}

export function useListings(params: ListingsParams) {
  return useQuery({
    queryKey: ['admin', 'listings', params],
    queryFn: () => fetchListings(params),
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}

export async function fetchListing(id: number): Promise<Listing> {
  const response = await api.get<{ success: boolean; data: Listing }>(`/admin/listings/${id}`);
  return response.data.data;
}

/**
 * A single listing by id, used to open a listing deep link even when the row is
 * not on the page the list happens to be showing.
 */
export function useListing(id: number | null) {
  return useQuery({
    queryKey: ['admin', 'listings', 'detail', id],
    queryFn: () => fetchListing(id as number),
    enabled: id !== null,
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 0,
  });
}

export function useApproveListing() {
  const invalidateListings = useInvalidateListings();

  return useMutation({
    mutationFn: (id: number) => moderate('approve', id),
    onSuccess: invalidateListings,
  });
}

export function useRejectListing() {
  const invalidateListings = useInvalidateListings();

  return useMutation({
    mutationFn: ({ id, adminNote }: { id: number; adminNote?: string }) =>
      moderate('reject', id, adminNote),
    onSuccess: invalidateListings,
  });
}

export function useDeactivateListing() {
  const invalidateListings = useInvalidateListings();

  return useMutation({
    mutationFn: (id: number) => moderate('deactivate', id),
    onSuccess: invalidateListings,
  });
}

export interface ReconcileInventoryInput {
  verified_physical_quantity: number;
  verified_externally_sold_quantity: number;
  accounted_transaction_ids: number[];
  reason: string;
  evidence?: string;
}

interface ReconcileInventoryResponse {
  success: boolean;
  message: string;
  data: {
    listing: Listing;
    reconciliation: NonNullable<Listing['latest_inventory_reconciliation']> & {
      listing_id: number;
      accounted_transaction_ids: number[];
    };
  };
}

export async function reconcileListingInventory(
  listingId: number,
  input: ReconcileInventoryInput,
): Promise<ReconcileInventoryResponse['data']> {
  const response = await api.post<ReconcileInventoryResponse>(
    `/admin/listings/${listingId}/inventory/reconcile`,
    input,
  );
  return response.data.data;
}

export function useReconcileListingInventory() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      listingId,
      input,
    }: {
      listingId: number;
      input: ReconcileInventoryInput;
    }) => reconcileListingInventory(listingId, input),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['admin', 'listings'] });
      void queryClient.invalidateQueries({ queryKey: ['admin', 'dashboard'] });
    },
  });
}

export interface ListingStatusCounts {
  total: number;
  pending: number;
  active: number;
  inactive: number;
}

/**
 * Aggregate listing counts for the status cards.
 *
 * There is no counting endpoint, and one is not needed: `GET /admin/listings`
 * already reports `pagination.total` for the query it ran, which is the server's
 * `count(*)`, not the size of the page it returned. Asking it once per status
 * with `per_page=1` therefore yields exact totals without a new backend surface.
 *
 * All four requests share one query key, so the cards have a single loading
 * state and the moderation mutations — which invalidate the `['admin',
 * 'listings']` prefix — refresh the counts along with the table.
 */
export function useListingCounts() {
  return useQuery({
    queryKey: ['admin', 'listings', 'counts'],
    queryFn: async (): Promise<ListingStatusCounts> => {
      const [all, pending, active, inactive] = await Promise.all([
        fetchListings({ per_page: 1 }),
        fetchListings({ status: 'pending', per_page: 1 }),
        fetchListings({ status: 'active', per_page: 1 }),
        fetchListings({ status: 'inactive', per_page: 1 }),
      ]);

      return {
        total: all.pagination.total,
        pending: pending.pagination.total,
        active: active.pagination.total,
        inactive: inactive.pagination.total,
      };
    },
    staleTime: 30_000,
  });
}
