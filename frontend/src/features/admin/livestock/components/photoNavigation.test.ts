import { describe, expect, it } from 'vitest';
import { clampPhotoIndex, photoPosition, stepPhotoIndex } from './photoNavigation';

describe('stepPhotoIndex', () => {
  it('moves to the next and previous photo', () => {
    expect(stepPhotoIndex(1, 4, 1)).toBe(2);
    expect(stepPhotoIndex(2, 4, -1)).toBe(1);
  });

  it('wraps from the last photo to the first, and back', () => {
    expect(stepPhotoIndex(3, 4, 1)).toBe(0);
    expect(stepPhotoIndex(0, 4, -1)).toBe(3);
  });

  it('stays on the only photo', () => {
    expect(stepPhotoIndex(0, 1, 1)).toBe(0);
    expect(stepPhotoIndex(0, 1, -1)).toBe(0);
  });

  it('does not move when there are no photos', () => {
    expect(stepPhotoIndex(0, 0, 1)).toBe(0);
  });

  it('recovers from a position past the end', () => {
    // A list that shrank while its position was held must not index off the end.
    expect(stepPhotoIndex(7, 3, 1)).toBe(0);
  });
});

describe('clampPhotoIndex', () => {
  it('keeps a position inside the list', () => {
    expect(clampPhotoIndex(-2, 3)).toBe(0);
    expect(clampPhotoIndex(1, 3)).toBe(1);
    expect(clampPhotoIndex(9, 3)).toBe(2);
  });

  it('is zero for an empty list', () => {
    expect(clampPhotoIndex(4, 0)).toBe(0);
  });
});

describe('photoPosition', () => {
  it('numbers photos from one', () => {
    expect(photoPosition(0, 5)).toBe('Photo 1 of 5');
    expect(photoPosition(4, 5)).toBe('Photo 5 of 5');
  });

  it('never reports a position outside the list', () => {
    expect(photoPosition(99, 5)).toBe('Photo 5 of 5');
  });
});
