import Foundation

enum StreamQuality: String, CaseIterable, Identifiable {
    case q240 = "240p"
    case q360 = "360p"
    case q480 = "480p"
    case q540 = "540p"
    case q720 = "720p"
    case q810 = "810p"
    case q1080 = "1080p"
    case q1080p60 = "1080p-60fps"

    var id: String { rawValue }

    var label: String {
        rawValue == "1080p-60fps" ? "1080p (60fps)" : rawValue
    }
}
