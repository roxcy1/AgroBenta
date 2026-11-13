import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

const ValueKey<String> termsAndConditionsAvailabilityKey = ValueKey<String>(
  'terms-and-conditions-availability',
);
const ValueKey<String> privacyPolicyAvailabilityKey = ValueKey<String>(
  'privacy-policy-availability',
);

/// Availability scaffold for legal documents awaiting approved final text.
///
/// This screen intentionally contains no legal provisions or document reader.
/// It can be connected to approved, bundled content once the project owner
/// provides it.
class TermsAndPoliciesScreen extends StatelessWidget {
  const TermsAndPoliciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Policies')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          children: <Widget>[
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Official documents',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Approved legal content is not available yet. Documents '
                      'will appear here when their final text is approved.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: <Widget>[
                          ListTile(
                            key: termsAndConditionsAvailabilityKey,
                            leading: const Icon(Icons.description_outlined),
                            title: const Text('Terms and Conditions'),
                            subtitle: const Text('Pending approved content'),
                            trailing: const Icon(Icons.lock_outline),
                            enabled: false,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            key: privacyPolicyAvailabilityKey,
                            leading: const Icon(Icons.privacy_tip_outlined),
                            title: const Text('Privacy Policy'),
                            subtitle: const Text('Pending approved content'),
                            trailing: const Icon(Icons.lock_outline),
                            enabled: false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
