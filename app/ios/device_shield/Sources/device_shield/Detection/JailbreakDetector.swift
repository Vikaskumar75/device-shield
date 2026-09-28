import Darwin
import Foundation

/// FR-02 (SRS section 5.2): heuristic jailbreak detection via five
/// independent signal categories. Every signal is individually weak
/// evidence; confidence is proportional to how many fire at once, the
/// same signal-count model `EmulatorDetector`/`DebuggerDetector` already
/// use. docs/features/ROOT_JAILBREAK_DETECTION.md.
///
/// Deliberately does **not** perform a full `_dyld_image_count`/image-
/// name scan for injected tweak dylibs — comprehensive runtime
/// injection/hook-framework scanning is a separate, already-planned P0
/// feature (FR-07, "Runtime Hook Detection: Frida, Xposed, Substrate,
/// Magisk modules"), and this detector shouldn't duplicate that scope.
/// [dyldEnvVarSet] below is a cheap, narrow check (one specific
/// environment variable), not that broader scan.
enum JailbreakDetector {
  private static let jailbreakAppPaths = [
    "/Applications/Cydia.app",
    "/Applications/Sileo.app",
    "/Applications/Zebra.app",
  ]

  private static let suspiciousSystemPaths = [
    "/Library/MobileSubstrate/MobileSubstrate.dylib",
    "/bin/bash",
    "/usr/sbin/sshd",
    "/etc/apt",
    "/private/var/lib/apt",
    "/var/lib/cydia",
    "/private/var/stash",
    "/usr/libexec/cydia",
    "/usr/bin/ssh",
  ]

  private static let signalCategoryCount = 5.0

  static func check() -> [String: Any] {
    #if targetEnvironment(simulator)
      // The Simulator can't be jailbroken, and its path and process checks
      // see the host Mac (e.g. /bin/bash), which would report a jailbreak.
      return [
        "detected": false,
        "confidence": 0.0,
        "signals": [String](),
        "applicable": false,
      ]
    #else
      return evaluate(
        jailbreakAppPathExists: jailbreakAppPaths.contains {
          FileManager.default.fileExists(atPath: $0)
        },
        suspiciousSystemPathExists: suspiciousSystemPaths.contains {
          FileManager.default.fileExists(atPath: $0)
        },
        writableOutsideSandbox: canWriteOutsideSandbox(),
        dyldEnvVarSet: !(ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"] ?? "")
          .isEmpty,
        processSpawnSucceeded: canSpawnProcess()
      )
    #endif
  }

  /// Pure decision logic, separated from the real filesystem/process
  /// reads in `check()` above so it can be unit-tested with synthetic
  /// inputs — the same split `EmulatorDetector`/`ScreenRecordingDetector`
  /// already document for the same reason.
  static func evaluate(
    jailbreakAppPathExists: Bool,
    suspiciousSystemPathExists: Bool,
    writableOutsideSandbox: Bool,
    dyldEnvVarSet: Bool,
    processSpawnSucceeded: Bool
  ) -> [String: Any] {
    var signals: [String] = []

    if jailbreakAppPathExists { signals.append("jailbreak_app_paths") }
    if suspiciousSystemPathExists { signals.append("suspicious_system_paths") }
    if writableOutsideSandbox { signals.append("writable_outside_sandbox") }
    if dyldEnvVarSet { signals.append("dyld_env_var") }
    if processSpawnSucceeded { signals.append("process_spawn_check") }

    let confidence = min(Double(signals.count) / signalCategoryCount, 1.0)
    return [
      "detected": !signals.isEmpty,
      "confidence": confidence,
      "signals": signals,
      "applicable": true,
    ]
  }

  /// Attempts to write, then immediately deletes, a file outside the
  /// app's sandbox container. Should fail with a permission error on a
  /// non-jailbroken device; succeeding is real evidence the sandbox is
  /// not enforced.
  private static func canWriteOutsideSandbox() -> Bool {
    let path = "/private/device_shield_jailbreak_test.txt"
    do {
      try "device_shield".write(toFile: path, atomically: true, encoding: .utf8)
      try FileManager.default.removeItem(atPath: path)
      return true
    } catch {
      return false
    }
  }

  /// SRS §5.2's "jailbreak APIs" category. `fork()` is the classic
  /// version of this check, but Swift's Darwin overlay marks it
  /// `unavailable` at compile time on this SDK
  /// (`@available(*, unavailable, message: "Please use threads or
  /// posix_spawn*()")`) — a hard compiler error, not a lint. Rather than
  /// route around that with `dlsym`/`dlopen` to reach the raw C symbol
  /// (which would cross into the same "circumventing a deliberate
  /// platform restriction" territory this SDK's `ScreenCaptureProtection
  /// .swift` already documents the risk of, and hasn't been separately
  /// approved for this detector), this uses `posix_spawn` — literally
  /// Apple's own suggested alternative in that error message, and a
  /// real, equivalent signal: a sandboxed, non-jailbroken app should not
  /// be able to spawn an arbitrary system binary as a child process
  /// either. Succeeding is real evidence sandboxing isn't enforced;
  /// failing is the expected, correct behavior on a real device.
  private static func canSpawnProcess() -> Bool {
    let path = "/bin/ls"
    guard FileManager.default.fileExists(atPath: path) else { return false }

    var pid: pid_t = 0
    let argv: [UnsafeMutablePointer<CChar>?] = [strdup(path), nil]
    defer { for arg in argv { free(arg) } }

    let status = posix_spawn(&pid, path, nil, nil, argv, environ)
    guard status == 0 else { return false }

    var waitStatus: Int32 = 0
    waitpid(pid, &waitStatus, 0)
    return true
  }
}
