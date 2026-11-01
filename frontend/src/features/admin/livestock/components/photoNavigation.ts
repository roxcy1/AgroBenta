/**
 * Pure helpers for the listing photo viewer.
 *
 * Kept apart from the component so the navigation rules can be tested without a
 * DOM, the same split `listingModeration.ts` uses.
 */

/** Keeps a position inside the list, so a photo list that shrinks cannot leave it pointing past the end. */
export function clampPhotoIndex(index: number, count: number): number {
  if (count <= 0) return 0;
  return Math.min(Math.max(index, 0), count - 1);
}

/** The position reached by stepping one photo in `direction`, wrapping at both ends. */
export function stepPhotoIndex(current: number, count: number, direction: 1 | -1): number {
  if (count <= 0) return 0;
  return (clampPhotoIndex(current, count) + direction + count) % count;
}

/** "Photo 2 of 5", for the caption and the image description. */
export function photoPosition(index: number, count: number): string {
  return `Photo ${clampPhotoIndex(index, count) + 1} of ${count}`;
}
