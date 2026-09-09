import Foundation

struct RTLHapticPattern {
    static let protocolVersion = 1
    static let maximumEventCount = 100
    static let maximumPatternDurationMilliseconds = 10_000
    static let maximumContinuousDurationMilliseconds = 3_000
    static let defaultIntensity = 0.5
    static let defaultSharpness = 0.5

    let version: Int
    let events: [Event]

    struct Event {
        enum Kind: String {
            case impact
            case continuous
        }

        let atMilliseconds: Int
        let kind: Kind
        let durationMilliseconds: Int?
        let intensity: Double
        let sharpness: Double
    }

    enum ValidationError: Error, Equatable, CustomStringConvertible {
        case invalidPayload
        case unsupportedVersion
        case invalidEvents
        case tooManyEvents
        case invalidEvent(Int)
        case unknownEventType(Int)
        case invalidTiming(Int)
        case invalidDuration(Int)
        case continuousDurationTooLong(Int)
        case invalidIntensity(Int)
        case invalidSharpness(Int)
        case patternTooLong

        var description: String {
            switch self {
            case .invalidPayload: return "payload must be an object"
            case .unsupportedVersion: return "only haptic protocol version 1 is supported"
            case .invalidEvents: return "events must be an array"
            case .tooManyEvents: return "patterns may contain at most 100 events"
            case .invalidEvent(let index): return "event \(index) must be an object"
            case .unknownEventType(let index): return "event \(index) has an unsupported type"
            case .invalidTiming(let index): return "event \(index) has an invalid at value"
            case .invalidDuration(let index): return "event \(index) has an invalid duration"
            case .continuousDurationTooLong(let index): return "event \(index) exceeds the continuous duration limit"
            case .invalidIntensity(let index): return "event \(index) has an invalid intensity"
            case .invalidSharpness(let index): return "event \(index) has an invalid sharpness"
            case .patternTooLong: return "pattern exceeds the total duration limit"
            }
        }
    }

    static func parse(payload: Any) throws -> RTLHapticPattern {
        guard let payload = payload as? [String: Any] else {
            throw ValidationError.invalidPayload
        }
        guard let version = integer(payload["version"]), version == protocolVersion else {
            throw ValidationError.unsupportedVersion
        }
        guard let rawEvents = payload["events"] as? [Any] else {
            throw ValidationError.invalidEvents
        }
        guard rawEvents.count <= maximumEventCount else {
            throw ValidationError.tooManyEvents
        }

        var parsedEvents: [Event] = []
        parsedEvents.reserveCapacity(rawEvents.count)
        var patternEnd = 0

        for (index, rawEvent) in rawEvents.enumerated() {
            guard let event = rawEvent as? [String: Any] else {
                throw ValidationError.invalidEvent(index)
            }
            guard let at = integer(event["at"]), at >= 0 else {
                throw ValidationError.invalidTiming(index)
            }
            guard let typeName = event["type"] as? String,
                  let kind = Event.Kind(rawValue: typeName) else {
                throw ValidationError.unknownEventType(index)
            }

            let duration: Int?
            switch kind {
            case .impact:
                duration = nil
            case .continuous:
                guard let parsedDuration = integer(event["duration"]), parsedDuration >= 0 else {
                    throw ValidationError.invalidDuration(index)
                }
                guard parsedDuration <= maximumContinuousDurationMilliseconds else {
                    throw ValidationError.continuousDurationTooLong(index)
                }
                duration = parsedDuration
            }

            let intensity = try normalizedValue(
                event["intensity"],
                defaultValue: defaultIntensity,
                error: .invalidIntensity(index)
            )
            let sharpness = try normalizedValue(
                event["sharpness"],
                defaultValue: defaultSharpness,
                error: .invalidSharpness(index)
            )

            let (eventEnd, overflow) = at.addingReportingOverflow(duration ?? 0)
            guard !overflow else { throw ValidationError.patternTooLong }
            patternEnd = max(patternEnd, eventEnd)
            guard patternEnd <= maximumPatternDurationMilliseconds else {
                throw ValidationError.patternTooLong
            }

            parsedEvents.append(Event(
                atMilliseconds: at,
                kind: kind,
                durationMilliseconds: duration,
                intensity: intensity,
                sharpness: sharpness
            ))
        }

        return RTLHapticPattern(
            version: version,
            events: parsedEvents.sorted { $0.atMilliseconds < $1.atMilliseconds }
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let doubleValue = number.doubleValue
        guard doubleValue.isFinite,
              doubleValue.rounded(.towardZero) == doubleValue,
              doubleValue >= Double(Int.min),
              doubleValue <= Double(Int.max) else {
            return nil
        }
        return Int(doubleValue)
    }

    private static func normalizedValue(
        _ value: Any?,
        defaultValue: Double,
        error: ValidationError
    ) throws -> Double {
        guard let value else { return defaultValue }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw error
        }
        let doubleValue = number.doubleValue
        guard doubleValue.isFinite, (0.0...1.0).contains(doubleValue) else {
            throw error
        }
        return doubleValue
    }
}
