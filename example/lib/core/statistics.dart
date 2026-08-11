/// Running counters the Statistics screen displays — purely local
/// bookkeeping derived from observing SDK calls/events, not an SDK type.
class Statistics {
  int screenshotsDetected = 0;
  int recordingStarted = 0;
  int recordingStopped = 0;
  int protectionEnabledCount = 0;
  int protectionDisabledCount = 0;
  int sdkInitializedCount = 0;
  int callbacksFired = 0;
  int eventsEmitted = 0;
  int errors = 0;
  int warnings = 0;

  void reset() {
    screenshotsDetected = 0;
    recordingStarted = 0;
    recordingStopped = 0;
    protectionEnabledCount = 0;
    protectionDisabledCount = 0;
    sdkInitializedCount = 0;
    callbacksFired = 0;
    eventsEmitted = 0;
    errors = 0;
    warnings = 0;
  }
}
