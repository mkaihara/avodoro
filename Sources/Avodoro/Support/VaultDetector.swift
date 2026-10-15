import Foundation

enum VaultDetector {
    /// The name of the Obsidian vault containing `folder` (the folder itself or a parent that
    /// holds a `.obsidian` directory), or nil.
    static func vaultName(containing folder: URL) -> String? {
        var path = folder.standardizedFileURL.path
        while true {
            var isDirectory: ObjCBool = false
            let marker = (path as NSString).appendingPathComponent(".obsidian")
            if FileManager.default.fileExists(atPath: marker, isDirectory: &isDirectory), isDirectory.boolValue {
                return (path as NSString).lastPathComponent
            }
            let parent = (path as NSString).deletingLastPathComponent
            if parent == path || parent.isEmpty { return nil }
            path = parent
        }
    }
}
