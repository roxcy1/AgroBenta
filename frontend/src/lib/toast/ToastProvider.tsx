import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';

export type ToastVariant = 'success' | 'error';

export interface Toast {
  id: number;
  variant: ToastVariant;
  message: string;
}

interface ToastContextValue {
  showToast: (variant: ToastVariant, message: string) => void;
  success: (message: string) => void;
  error: (message: string) => void;
  dismiss: (id: number) => void;
}

/** How long a toast stays before it dismisses itself. */
export const TOAST_DURATION_MS = 6000;

const ToastContext = createContext<ToastContextValue | undefined>(undefined);

/**
 * App-wide transient feedback.
 *
 * Deliberately small and dependency-free: a queue of messages with an
 * auto-dismiss timer. It is mounted once near the root so any page can report
 * the outcome of an action without being wrapped in its own notification UI.
 * Errors are announced assertively (`role="alert"`), successes politely.
 */
export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const nextId = useRef(0);
  const timers = useRef(new Map<number, ReturnType<typeof setTimeout>>());

  const dismiss = useCallback((id: number) => {
    setToasts((current) => current.filter((toast) => toast.id !== id));

    const timer = timers.current.get(id);
    if (timer !== undefined) {
      clearTimeout(timer);
      timers.current.delete(id);
    }
  }, []);

  const showToast = useCallback(
    (variant: ToastVariant, message: string) => {
      const id = nextId.current;
      nextId.current += 1;

      setToasts((current) => [...current, { id, variant, message }]);

      const timer = setTimeout(() => dismiss(id), TOAST_DURATION_MS);
      timers.current.set(id, timer);
    },
    [dismiss],
  );

  useEffect(() => {
    const pending = timers.current;

    return () => {
      for (const timer of pending.values()) {
        clearTimeout(timer);
      }
      pending.clear();
    };
  }, []);

  const value = useMemo<ToastContextValue>(
    () => ({
      showToast,
      success: (message: string) => showToast('success', message),
      error: (message: string) => showToast('error', message),
      dismiss,
    }),
    [showToast, dismiss],
  );

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div className="toast-region" aria-live="polite">
        {toasts.map((toast) => (
          <div
            key={toast.id}
            className={`toast toast--${toast.variant}`}
            role={toast.variant === 'error' ? 'alert' : 'status'}
          >
            <span className="toast-message">{toast.message}</span>
            <button
              type="button"
              className="toast-dismiss"
              aria-label="Dismiss notification"
              onClick={() => dismiss(toast.id)}
            >
              Dismiss
            </button>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components -- standard context pattern
export function useToast(): ToastContextValue {
  const context = useContext(ToastContext);

  if (context === undefined) {
    throw new Error('useToast must be used within a ToastProvider');
  }

  return context;
}
