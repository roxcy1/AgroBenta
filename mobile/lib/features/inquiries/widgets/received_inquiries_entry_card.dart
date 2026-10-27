import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../view/received_inquiries_screen.dart';

/// The Seller Home entry point into the seller's received inquiries.
///
/// A link, not a counter. The list needs a request, and turning a navigation
/// element into a request on every Home build would make the landing screen
/// fetch data it does not display. The screen itself loads the first page.
///
/// Located on Seller Home rather than in the five-tab navigation: the shell's
/// destinations are fixed, and received inquiries are a seller sub-screen, like
/// listing management from Buyer Mode.
class ReceivedInquiriesEntryCard extends StatelessWidget {
  const ReceivedInquiriesEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Received Inquiries', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Read the questions buyers have sent about your listings.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      const ReceivedInquiriesScreen(),
                ),
              ),
              icon: const Icon(Icons.mark_email_unread_outlined, size: 18),
              label: const Text('View received inquiries'),
            ),
          ],
        ),
      ),
    );
  }
}
