/** @vitest-environment jsdom */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { DocumentViewer } from './VerificationDocuments';

const createObjectURL = vi.fn(() => 'blob:document');
const revokeObjectURL = vi.fn();

beforeEach(() => {
  // jsdom has no object URLs.
  Object.assign(URL, { createObjectURL, revokeObjectURL });
});

afterEach(() => {
  cleanup();
  createObjectURL.mockClear();
  revokeObjectURL.mockClear();
});

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

describe('DocumentViewer preview', () => {
  it('fetches on mount and shows the document as a thumbnail', async () => {
    const fetchDocument = vi.fn().mockResolvedValue(new Blob(['x']));

    render(<DocumentViewer preview present label="Selfie holding ID" fetchDocument={fetchDocument} />);

    expect(await screen.findByRole('button', { name: 'View Selfie holding ID full size' })).toBeTruthy();
    expect(fetchDocument).toHaveBeenCalledTimes(1);
  });

  it('offers Retry after a failed load, and Retry fetches again', async () => {
    const fetchDocument = vi
      .fn()
      .mockRejectedValueOnce(new Error('network'))
      .mockResolvedValueOnce(new Blob(['x']));

    render(<DocumentViewer preview present label="Proof of address" fetchDocument={fetchDocument} />);

    expect(await screen.findByText(/Failed to load document/)).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Retry' }));

    expect(await screen.findByRole('button', { name: 'View Proof of address full size' })).toBeTruthy();
    expect(screen.queryByText(/Failed to load document/)).toBeNull();
    expect(fetchDocument).toHaveBeenCalledTimes(2);
  });

  it('does not fetch a document that is not on file', () => {
    const fetchDocument = vi.fn();

    render(<DocumentViewer preview present={false} label="Selfie holding ID" fetchDocument={fetchDocument} />);

    expect(screen.getByText(/Not provided/)).toBeTruthy();
    expect(fetchDocument).not.toHaveBeenCalled();
  });

  it('revokes the object URL when it unmounts', async () => {
    const fetchDocument = vi.fn().mockResolvedValue(new Blob(['x']));
    const { unmount } = render(
      <DocumentViewer preview present label="Selfie holding ID" fetchDocument={fetchDocument} />,
    );
    await screen.findByRole('button', { name: 'View Selfie holding ID full size' });

    unmount();

    expect(revokeObjectURL).toHaveBeenCalledWith('blob:document');
  });
});

describe('DocumentViewer lightbox', () => {
  it('closes on Escape without letting the dialog behind it see the key', async () => {
    const outerEscape = vi.fn();
    window.addEventListener('keydown', outerEscape);
    const fetchDocument = vi.fn().mockResolvedValue(new Blob(['x']));

    render(<DocumentViewer preview present label="Government ID — Front" fetchDocument={fetchDocument} />);
    fireEvent.click(await screen.findByRole('button', { name: 'View Government ID — Front full size' }));
    expect(screen.getByRole('dialog', { name: 'Government ID — Front document' })).toBeTruthy();

    fireEvent.keyDown(window, { key: 'Escape' });

    expect(screen.queryByRole('dialog', { name: 'Government ID — Front document' })).toBeNull();
    expect(outerEscape).not.toHaveBeenCalled();
    // The thumbnail keeps its image after the lightbox closes.
    expect(screen.getByRole('button', { name: 'View Government ID — Front full size' })).toBeTruthy();

    window.removeEventListener('keydown', outerEscape);
  });
});

describe('DocumentViewer on demand', () => {
  it('fetches only when View is clicked', async () => {
    const fetchDocument = vi.fn().mockResolvedValue(new Blob(['x']));

    render(<DocumentViewer present label="Farm photo 1" fetchDocument={fetchDocument} />);
    expect(fetchDocument).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole('button', { name: 'View' }));

    expect(await screen.findByRole('dialog', { name: 'Farm photo 1 document' })).toBeTruthy();
    expect(fetchDocument).toHaveBeenCalledTimes(1);
  });

  it('creates no object URL when the fetch finishes after unmount', async () => {
    const pending = deferred<Blob>();
    const fetchDocument = vi.fn(() => pending.promise);

    const { unmount } = render(<DocumentViewer present label="Farm photo 1" fetchDocument={fetchDocument} />);
    fireEvent.click(screen.getByRole('button', { name: 'View' }));
    unmount();

    await act(async () => {
      pending.resolve(new Blob(['x']));
      await pending.promise;
    });

    await waitFor(() => expect(createObjectURL).not.toHaveBeenCalled());
  });
});
