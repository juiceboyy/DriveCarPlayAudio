import Foundation

struct DriveFile: Identifiable, Hashable {
    let id: String
    let name: String
    let mimeType: String
    let size: Int64?
    let parents: [String]?

    var isFolder: Bool {
        mimeType == "application/vnd.google-apps.folder"
    }

    var isAudio: Bool {
        let audioMIMEs = ["audio/mpeg", "audio/wav", "audio/x-wav",
                          "audio/aiff", "audio/x-aiff", "audio/mp4",
                          "audio/x-m4a", "audio/flac", "audio/ogg"]
        if audioMIMEs.contains(mimeType) { return true }
        let lower = name.lowercased()
        return lower.hasSuffix(".mp3") || lower.hasSuffix(".wav") ||
               lower.hasSuffix(".aif") || lower.hasSuffix(".aiff") ||
               lower.hasSuffix(".m4a") || lower.hasSuffix(".flac")
    }

    var displayMimeLabel: String {
        switch mimeType {
        case "audio/wav", "audio/x-wav":        return "WAV"
        case "audio/mpeg":                      return "MP3"
        case "audio/aiff", "audio/x-aiff":     return "AIFF"
        case "audio/mp4", "audio/x-m4a":       return "M4A"
        case "audio/flac":                      return "FLAC"
        default:
            if let ext = name.split(separator: ".").last { return ext.uppercased() }
            return "Audio"
        }
    }
}
