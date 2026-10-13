#if canImport(Darwin)
import CoreFoundation
#endif
import Foundation
import Synchronization

/// Announces that a sticky was created, edited or removed by any process
/// sharing the store, this one included.
///
/// The Darwin notification carries no payload, so a listener reads the store
/// again and compares. That is the only cross-process channel a sandboxed
/// process may use without an entitlement.
///
/// A change made in this process is also signalled in-process, so a sticky
/// created here appears without depending on the system delivering its own
/// notification back. Darwin stays for the other process.
public enum StickyChanges {
    private static let localObservers = Mutex<[UUID: AsyncStream<Void>.Continuation]>([:])

    /// Tells the other processes sharing the store that it changed.
    static func notifyOtherProcesses() {
        #if canImport(Darwin)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: StickyKitIdentity.changesDarwinName as CFString),
            nil,
            nil,
            true
        )
        #endif
    }

    /// Tells every stream in this process that the store changed.
    public static func notifyInProcess() {
        let continuations = localObservers.withLock { Array($0.values) }
        for continuation in continuations { continuation.yield() }
    }

    /// A stream that yields once per announcement, coalescing a burst.
    /// Observation ends when the stream's consumer stops.
    public static func stream() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let localID = UUID()
            localObservers.withLock { $0[localID] = continuation }
            #if canImport(Darwin)
            let relay = Relay(continuation: continuation)
            let name = StickyKitIdentity.changesDarwinName
            let center = CFNotificationCenterGetDarwinNotifyCenter()

            CFNotificationCenterAddObserver(
                center,
                Unmanaged.passRetained(relay).toOpaque(),
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    Unmanaged<Relay>.fromOpaque(observer).takeUnretainedValue()
                        .continuation.yield()
                },
                name as CFString,
                nil,
                .deliverImmediately
            )
            #endif

            continuation.onTermination = { _ in
                localObservers.withLock { _ = $0.removeValue(forKey: localID) }
                #if canImport(Darwin)
                let observer = Unmanaged.passUnretained(relay).toOpaque()
                CFNotificationCenterRemoveObserver(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    observer,
                    CFNotificationName(rawValue: name as CFString),
                    nil
                )
                Unmanaged<Relay>.fromOpaque(observer).release()
                #endif
            }
        }
    }

    private final class Relay: Sendable {
        let continuation: AsyncStream<Void>.Continuation

        init(continuation: AsyncStream<Void>.Continuation) {
            self.continuation = continuation
        }
    }
}
