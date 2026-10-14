import { describe, expect, it } from 'vitest';
import { buildPageWindow } from './pagination';

describe('buildPageWindow', () => {
  it('shows a single page when there is only one page', () => {
    expect(buildPageWindow(1, 1)).toEqual([1]);
  });

  it('lists every page when they all fit without gaps', () => {
    expect(buildPageWindow(1, 3)).toEqual([1, 2, 3]);
    expect(buildPageWindow(3, 3)).toEqual([1, 2, 3]);
  });

  it('collapses the gap on both sides of a middle page', () => {
    expect(buildPageWindow(5, 10)).toEqual([1, 'ellipsis', 4, 5, 6, 'ellipsis', 10]);
  });

  it('collapses only the trailing gap while on the first page', () => {
    expect(buildPageWindow(1, 10)).toEqual([1, 2, 'ellipsis', 10]);
  });

  it('collapses only the leading gap while on the last page', () => {
    expect(buildPageWindow(10, 10)).toEqual([1, 'ellipsis', 9, 10]);
  });

  it('always includes the first and last page', () => {
    for (const current of [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
      const window = buildPageWindow(current, 10);
      expect(window[0]).toBe(1);
      expect(window[window.length - 1]).toBe(10);
    }
  });

  it('keeps the current page inside the window', () => {
    for (const current of [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
      expect(buildPageWindow(current, 10)).toContain(current);
    }
  });

  it('clamps an out-of-range current page to a valid window', () => {
    expect(buildPageWindow(0, 5)).toEqual([1, 2, 'ellipsis', 5]);
    expect(buildPageWindow(99, 5)).toEqual([1, 'ellipsis', 4, 5]);
  });

  it('never emits two adjacent ellipses', () => {
    for (let total = 1; total <= 40; total += 1) {
      for (let current = 1; current <= total; current += 1) {
        const window = buildPageWindow(current, total);
        for (let i = 1; i < window.length; i += 1) {
          expect(window[i] === 'ellipsis' && window[i - 1] === 'ellipsis').toBe(false);
        }
      }
    }
  });
});
