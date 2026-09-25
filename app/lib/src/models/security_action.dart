/// Placeholder shell — Phase 3 ("Core Models") owns the complete definition.
///
/// Exists now only so the [Rule] and [PolicyManager] contracts in Phase 2
/// have a real return type instead of `dynamic`. This vocabulary is generic
/// policy-response language, not tied to any specific detector or rule —
/// `custom` is the reserved extension slot for actions registered against
/// an `ActionHandler` rather than requiring a new enum value.
enum SecurityAction { ignore, warn, block, logout, terminate, report, custom }
