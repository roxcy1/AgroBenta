import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/transaction_receipt.dart';
import '../../marketplace/widgets/marketplace_state_views.dart';
import '../../transactions/state/transaction_scope.dart';
import '../services/receipt_gallery_saver.dart';
import '../services/receipt_png_exporter.dart';
import '../state/transaction_receipt_controller.dart';
import '../state/transaction_receipt_state.dart';
import '../widgets/transaction_receipt_card.dart';

/// The completed sale's receipt, from `GET /transactions/{id}/receipt`.
///
/// Reached automatically after the buyer confirms receipt and from the completed
/// transaction detail. The screen only renders the server's snapshot; it never
/// assembles or recomputes a receipt value.
class TransactionReceiptScreen extends StatelessWidget {
  const TransactionReceiptScreen({
    required this.transactionId,
    this.gallerySaver = const GalReceiptGallerySaver(),
    this.pngExporter = const RepaintBoundaryPngExporter(),
    super.key,
  });

  final int transactionId;

  /// Injected in tests; the app uses the real gallery saver.
  final ReceiptGallerySaver gallerySaver;

  /// Injected in tests; the app uses the real raster capture.
  final ReceiptPngExporter pngExporter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purchase Receipt')),
      body: SafeArea(
        child: _ReceiptBody(
          transactionId: transactionId,
          gallerySaver: gallerySaver,
          pngExporter: pngExporter,
        ),
      ),
    );
  }
}

class _ReceiptBody extends StatefulWidget {
  const _ReceiptBody({
    required this.transactionId,
    required this.gallerySaver,
    required this.pngExporter,
  });

  final int transactionId;
  final ReceiptGallerySaver gallerySaver;
  final ReceiptPngExporter pngExporter;

  @override
  State<_ReceiptBody> createState() => _ReceiptBodyState();
}

class _ReceiptBodyState extends State<_ReceiptBody> {
  late final TransactionReceiptController _controller;
  final GlobalKey _receiptKey = GlobalKey();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TransactionReceiptController(
      TransactionScope.readOf(context),
      widget.transactionId,
    );
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? child) {
        final TransactionReceiptState state = _controller.state;

        if (state.isLoading) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: AppSpacing.md),
                Text('Loading receipt'),
              ],
            ),
          );
        }

        if (state.isUnavailable) {
          return const _UnavailableNotice();
        }

        if (state.status == TransactionReceiptStatus.failed) {
          return MarketplaceErrorState(
            title: 'Could not load receipt',
            message: state.errorMessage ?? 'Something went wrong.',
            onRetry: _controller.load,
          );
        }

        final receipt = state.receipt;
        if (receipt == null) {
          return const SizedBox.shrink();
        }

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          children: <Widget>[
            RepaintBoundary(
              key: _receiptKey,
              child: TransactionReceiptCard(receipt: receipt),
            ),
            const SizedBox(height: AppSpacing.md),
            if (kIsWeb)
              Text(
                'Saving to the gallery is available in the Android and iOS app.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _saveReceipt(receipt),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Save to Gallery'),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Captures the receipt card at a high-resolution pixel ratio.
  ///
  /// The exporter owns the raster work; the screen only decides when it runs.
  Future<Uint8List> _capturePng() => widget.pngExporter.capture(_receiptKey);

  Future<void> _saveReceipt(TransactionReceipt receipt) async {
    if (_saving) {
      return;
    }

    setState(() => _saving = true);

    try {
      final Uint8List bytes = await _capturePng();
      await widget.gallerySaver.save(
        bytes,
        name: 'agrobenta-receipt-${receipt.reference}',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt saved to your gallery.')),
      );
    } on ReceiptGalleryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on Object {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save the receipt. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

/// Shown when the record has no receipt or is not visible to this user.
class _UnavailableNotice extends StatelessWidget {
  const _UnavailableNotice();

  @override
  Widget build(BuildContext context) {
    final TextTheme theme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.receipt_long_outlined,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'This receipt is not available',
              style: theme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Only a completed transaction has a receipt, and only its buyer '
              'or seller can read it.',
              style: theme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back to transaction'),
            ),
          ],
        ),
      ),
    );
  }
}
