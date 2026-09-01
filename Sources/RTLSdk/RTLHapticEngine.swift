import CoreHaptics
import Foundation

final class RTLHapticEngine {
    private var engine: CHHapticEngine?
    private var activePlayers: [UUID: CHHapticPatternPlayer] = [:]

    var capabilities: [String: Any] {
        let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        return [
            "supported": supported,
            "protocolVersion": RTLHapticPattern.protocolVersion,
            "impact": supported,
            "continuous": supported,
            "intensity": supported,
            "sharpness": supported
        ]
    }

    func play(_ pattern: RTLHapticPattern) {
        guard !pattern.events.isEmpty else {
            print("[RTLSdk][Haptics] Ignored empty pattern")
            return
        }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("[RTLSdk][Haptics] Device does not support Core Haptics")
            return
        }

        do {
            let engine = try preparedEngine()
            let events = pattern.events.compactMap(makeEvent)
            guard !events.isEmpty else { return }
            let hapticPattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: hapticPattern)
            try player.start(atTime: CHHapticTimeImmediate)
            retain(player, for: pattern)
            print("[RTLSdk][Haptics] Started pattern with \(events.count) event(s)")
        } catch {
            print("[RTLSdk][Haptics] Unable to play pattern: \(error.localizedDescription)")
        }
    }

    func stop() {
        activePlayers.removeAll()
        engine?.stop(completionHandler: nil)
        engine = nil
    }

    private func preparedEngine() throws -> CHHapticEngine {
        if let engine {
            try engine.start()
            return engine
        }

        let newEngine = try CHHapticEngine()
        newEngine.isAutoShutdownEnabled = true
        newEngine.stoppedHandler = { reason in
            print("[RTLSdk] Haptic engine stopped (reason: \(reason.rawValue))")
        }
        newEngine.resetHandler = { [weak self, weak newEngine] in
            guard self?.engine === newEngine else { return }
            do {
                try newEngine?.start()
            } catch {
                print("[RTLSdk] Unable to restart haptic engine after reset: \(error.localizedDescription)")
            }
        }
        try newEngine.start()
        engine = newEngine
        return newEngine
    }

    private func makeEvent(_ event: RTLHapticPattern.Event) -> CHHapticEvent? {
        let parameters = [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(event.intensity)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(event.sharpness))
        ]
        let relativeTime = TimeInterval(event.atMilliseconds) / 1_000.0

        switch event.kind {
        case .impact:
            return CHHapticEvent(
                eventType: .hapticTransient,
                parameters: parameters,
                relativeTime: relativeTime
            )
        case .continuous:
            guard let duration = event.durationMilliseconds, duration > 0 else { return nil }
            return CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: parameters,
                relativeTime: relativeTime,
                duration: TimeInterval(duration) / 1_000.0
            )
        }
    }

    private func retain(_ player: CHHapticPatternPlayer, for pattern: RTLHapticPattern) {
        let identifier = UUID()
        activePlayers[identifier] = player

        let patternDuration = pattern.events.reduce(0.0) { duration, event in
            let eventEnd = Double(event.atMilliseconds + (event.durationMilliseconds ?? 0)) / 1_000.0
            return max(duration, eventEnd)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + patternDuration + 0.5) { [weak self] in
            self?.activePlayers.removeValue(forKey: identifier)
        }
    }
}
