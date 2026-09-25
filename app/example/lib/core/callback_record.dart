/// Tracks one `DeviceShield.registerCallback(name, ...)` registration —
/// the Callbacks screen's own bookkeeping, not an SDK type.
class CallbackRecord {
  CallbackRecord({required this.name});

  final String name;
  bool registered = true;
  int invocationCount = 0;
  dynamic lastPayload;
  DateTime? lastInvokedAt;

  void recordInvocation(dynamic payload) {
    invocationCount++;
    lastPayload = payload;
    lastInvokedAt = DateTime.now();
  }
}
