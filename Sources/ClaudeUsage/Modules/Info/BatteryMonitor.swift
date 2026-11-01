import Combine
import Foundation
import IOKit.ps

/// Battery level and charging state, updated by IOKit when the power source changes (no polling).
@MainActor
final class BatteryMonitor: ObservableObject {
    struct Reading: Equatable {
        /// 0–100.
        var percent: Int
        var charging: Bool
        /// Plugged into power (charging or full).
        var onPower: Bool
    }

    /// nil on a Mac without a battery.
    @Published private(set) var reading: Reading?
    /// Fires when the charger is plugged in.
    let pluggedIn = PassthroughSubject<Reading, Never>()

    private var source: CFRunLoopSource?

    init(live: Bool = true) {
        guard live else { return }
        reading = Self.read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.update(BatteryMonitor.read()) }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    /// Applies a new reading; plugging in (from battery to power) fires `pluggedIn`. The self-test calls it directly.
    func update(_ next: Reading?) {
        let wasOnPower = reading?.onPower
        guard next != reading else { return }
        reading = next
        if let next, wasOnPower == false, next.onPower { pluggedIn.send(next) }
    }

    nonisolated private static func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            return Reading(percent: max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current,
                           charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                           onPower: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
        }
        return nil
    }
}
