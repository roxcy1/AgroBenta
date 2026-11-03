import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/popular_livestock_category.dart';
import '../../../repositories/marketplace_repository.dart';

/// Lifecycle of the Popular Livestock ranking on Buyer Home.
enum PopularLivestockStatus { initial, loading, ready, failed }

/// Presentation logic for the Buyer Home "Popular Livestock" section.
///
/// The ranking comes from its own endpoint (completed sales in the last 30
/// days), so it is loaded independently of the browse list and never re-queries
/// on search or filter changes. Owner per Home screen.
class PopularLivestockController extends ChangeNotifier {
  PopularLivestockController(this._repository);

  final MarketplaceRepository _repository;

  PopularLivestockStatus _status = PopularLivestockStatus.initial;
  List<PopularLivestockCategory> _categories =
      const <PopularLivestockCategory>[];
  String? _errorMessage;

  bool _disposed = false;
  bool _loading = false;

  PopularLivestockStatus get status => _status;
  List<PopularLivestockCategory> get categories => _categories;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    if (_loading) {
      return;
    }
    _loading = true;
    _publish(PopularLivestockStatus.loading, clearError: true);

    try {
      final List<PopularLivestockCategory> categories = await _repository
          .popularLivestock();
      if (_disposed) {
        return;
      }
      _categories = categories;
      _publish(PopularLivestockStatus.ready);
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      _errorMessage = error.message;
      _publish(PopularLivestockStatus.failed);
    } on Object {
      if (_disposed) {
        return;
      }
      _errorMessage = 'Something went wrong. Please try again.';
      _publish(PopularLivestockStatus.failed);
    } finally {
      _loading = false;
    }
  }

  void _publish(PopularLivestockStatus status, {bool clearError = false}) {
    if (_disposed) {
      return;
    }
    _status = status;
    if (clearError) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
