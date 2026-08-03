import Foundation

/// FR-04 (SRS section 5.4): debugger detection.
///
/// Uses Apple's own documented technique (Technical Q&A QA1361) for
/// detecting an attached debugger: query this process's own `kinfo_proc`
/// via `sysctl` and check the `P_TRACED` flag. This is a single,
/// authoritative binary signal — unlike Android's weighted heuristic-count
/// model, a detected debugger here is reported at full confidence, the
/// same "exact, not heuristic" style `EmulatorDetector.swift` already uses
/// for its own compile-time simulator check.
enum DebuggerDetector {
  static func check() -> [String: Any] {
    return evaluate(debuggerAttached: isDebuggerAttached())
  }

  /// Pure decision logic, separated from the actual `sysctl` syscall in
  /// [isDebuggerAttached] below so it can be unit-tested with a synthetic
  /// input — mirrors the `evaluate(...)` split
  /// `android/.../detection/DebuggerDetector.kt` already uses for the same
  /// reason on its own platform.
  static func evaluate(debuggerAttached: Bool) -> [String: Any] {
    return [
      "detected": debuggerAttached,
      "confidence": debuggerAttached ? 1.0 : 0.0,
      "signals": debuggerAttached ? ["ptrace_flag"] : [String](),
    ]
  }

  /// Apple Technical Q&A QA1361: a debugger attaches to a process via
  /// `ptrace`, which sets `P_TRACED` in the process's `kinfo_proc.kp_proc.p_flag`.
  /// `sysctl` with `{CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()}` is the
  /// documented, supported way to read it back for the calling process.
  private static func isDebuggerAttached() -> Bool {
    var info = kinfo_proc()
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    var size = MemoryLayout<kinfo_proc>.stride

    let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
    guard result == 0 else {
      // A failed sysctl call is not itself evidence of anything — treat
      // it the same as "not traced" rather than reporting a false
      // positive off a transport-level failure.
      return false
    }
    return (info.kp_proc.p_flag & P_TRACED) != 0
  }
}
