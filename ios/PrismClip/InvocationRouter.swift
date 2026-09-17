import Foundation

/// Decides which of several URLs delivered in one foreground activation should win.
///
/// The system does not tell us that two deliveries belong together, and a machine link can be
/// replayed when the App Clip is reactivated while a Live Activity tap arrives as a separate
/// explicit open. Ordering by arrival time made that a race, and ordering by URL shape is wrong
/// because a bare `/t/{shop}` link is a legitimate App Clip invocation too.
///
/// What the system does give us is *provenance*: each callback names where its URL came from.
/// That is kept here and used to rank deliveries, so the outcome does not depend on timing.
@MainActor
final class InvocationRouter {
  enum Source {
    /// `NSUserActivityTypeBrowsingWeb`: the App Clip invocation, or a replay of it when the
    /// clip is reactivated. It carries the URL the clip was originally opened with, so it can
    /// be stale relative to what the player just did.
    case appClipInvocation
    /// `onOpenURL`: a URL the player opened just now. A Live Activity with a `widgetURL`
    /// arrives here.
    case explicitOpenURL
    /// `NSUserActivityTypeLiveActivity`: a Live Activity tap whose activity carries no URL of
    /// its own, so the link it was started for is reused. Equally current as an explicit open.
    case liveActivity

    /// Higher wins within one activation. The two current sources rank together, above a
    /// replayed invocation; spelling the ranks out keeps that intent readable.
    var rank: Int {
      switch self {
      case .appClipInvocation: return 1
      case .explicitOpenURL, .liveActivity: return 2
      }
    }
  }

  /// The strongest source seen since the scene last entered the background. Only ever raised:
  /// a replayed invocation arriving later in the same activation must not displace what the
  /// player explicitly opened.
  private var highestRank = 0

  /// Called when the scene reaches the background. A later activation starts clean, so a fresh
  /// App Clip invocation is allowed to take effect again.
  ///
  /// Deliberately not called for `.inactive`: a normal foreground/background transition passes
  /// through it, and resetting there would let a replay win mid-activation.
  func resetForNextActivation() {
    highestRank = 0
  }

  /// Returns whether `source` may take over the page, and records it when it may.
  func shouldAccept(_ source: Source) -> Bool {
    guard source.rank >= highestRank else { return false }
    highestRank = source.rank
    return true
  }

  /// Routes a delivery, dropping it when a stronger source already won this activation.
  func handle(_ url: URL, source: Source, model: MachineLoginViewModel) async {
    guard shouldAccept(source) else { return }
    await model.handleResolvedInvocation(url)
  }
}
