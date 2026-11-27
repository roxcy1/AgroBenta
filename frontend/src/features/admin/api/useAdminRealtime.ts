import { useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { connectAdminRealtime } from '../../../lib/realtime';
import { invalidateForActivity, invalidateForUserReport } from './adminRealtimeInvalidation';

export { invalidateForActivity, invalidateForUserReport } from './adminRealtimeInvalidation';

/**
 * Subscribe the Admin Web to real-time activity. Mounted once by the admin
 * layout, so every admin page shares one socket and one listener.
 */
export function useAdminRealtime(): void {
  const queryClient = useQueryClient();

  useEffect(() => {
    return connectAdminRealtime(
      (event) => {
        invalidateForActivity(queryClient, event);
      },
      () => {
        // A reconnect may have missed activities while the socket was down;
        // refresh every admin surface once.
        void queryClient.invalidateQueries({ queryKey: ['admin'] });
      },
      () => {
        void queryClient.invalidateQueries({ queryKey: ['admin', 'listings'] });
      },
      () => {
        invalidateForUserReport(queryClient);
      },
    );
  }, [queryClient]);
}
