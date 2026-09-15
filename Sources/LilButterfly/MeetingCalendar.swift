#if canImport(EventKit)
import EventKit

struct VideoMeeting {
    let identifier: String
    let startDate: Date
}

final class MeetingCalendar {
    private let store = EKEventStore()
    private var hasAccess = false

    func requestAccess(completion: @escaping @Sendable (Bool) -> Void) {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            hasAccess = true
            completion(true)
        case .notDetermined:
            store.requestFullAccessToEvents { [weak self] granted, _ in
                self?.hasAccess = granted
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func nextVideoMeeting(from now: Date = Date()) -> VideoMeeting? {
        guard hasAccess else { return nil }
        let end = now.addingTimeInterval(24 * 60 * 60)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter(isVideoMeeting)
            .sorted { $0.startDate < $1.startDate }
            .first
            .map { VideoMeeting(identifier: $0.eventIdentifier, startDate: $0.startDate) }
    }

    func isVideoMeetingActive(at date: Date = Date()) -> Bool {
        guard hasAccess else { return false }
        let predicate = store.predicateForEvents(
            withStart: date.addingTimeInterval(-12 * 60 * 60),
            end: date.addingTimeInterval(24 * 60 * 60),
            calendars: nil
        )
        return store.events(matching: predicate).contains {
            isVideoMeeting($0) && $0.startDate <= date && $0.endDate > date
        }
    }

    private func isVideoMeeting(_ event: EKEvent) -> Bool {
        let text = [event.title, event.location, event.notes, event.url?.absoluteString]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return ["zoom.us", "zoom meeting", "teams.microsoft", "microsoft teams",
                "meet.google", "google meet"].contains { text.contains($0) }
    }
}
#else
struct VideoMeeting {
    let identifier: String
    let startDate: Date
}

final class MeetingCalendar {
    func requestAccess(completion: @escaping @Sendable (Bool) -> Void) { completion(false) }
    func nextVideoMeeting(from now: Date = Date()) -> VideoMeeting? { nil }
    func isVideoMeetingActive(at date: Date = Date()) -> Bool { false }
}
#endif
