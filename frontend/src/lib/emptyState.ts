/**
 * The plain message for a list with nothing in it, worded the same on every page
 * (DESIGN.md §14: "No transactions available yet.").
 *
 * With no filters the list is empty because nothing exists yet; with filters it
 * is empty because nothing matches them, which is a different thing to tell the
 * administrator.
 */
export function emptyListMessage(subject: string, filtered: boolean): string {
  return filtered
    ? `No ${subject} match the current filters.`
    : `No ${subject} available yet.`;
}
