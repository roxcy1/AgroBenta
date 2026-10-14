export type PageItem = number | 'ellipsis';

export const PAGE_ELLIPSIS = 'ellipsis';

/**
 * Builds the window of page numbers to show in a pager.
 *
 * The first and last page are always included, plus the pages immediately
 * around the current page. Gaps between selected pages are collapsed into a
 * single `ellipsis` marker. Inputs are clamped so a stale or malformed
 * pagination payload cannot produce an out-of-range control.
 */
export function buildPageWindow(
  currentPage: number,
  lastPage: number,
  siblingCount = 1,
): PageItem[] {
  const total = Math.max(1, Math.floor(lastPage));
  const current = Math.min(Math.max(1, Math.floor(currentPage)), total);
  const siblings = Math.max(0, Math.floor(siblingCount));

  const pages = new Set<number>([1, total]);
  for (let page = current - siblings; page <= current + siblings; page += 1) {
    if (page >= 1 && page <= total) {
      pages.add(page);
    }
  }

  const sorted = [...pages].sort((a, b) => a - b);
  const items: PageItem[] = [];
  let previous = 0;

  for (const page of sorted) {
    if (previous !== 0 && page - previous > 1) {
      items.push(PAGE_ELLIPSIS);
    }
    items.push(page);
    previous = page;
  }

  return items;
}
