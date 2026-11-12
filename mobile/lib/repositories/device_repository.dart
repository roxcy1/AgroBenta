import '../services/device_service.dart';

/// Push registration orchestration over [DeviceService].
///
/// Thin today: the backend owns the device's lifecycle (it deletes the
/// registration with the session's token on logout), so registering is the
/// only client-side step.
class DeviceRepository {
  const DeviceRepository(this._service);

  final DeviceService _service;

  Future<void> registerPushToken(String token) => _service.register(token);
}
