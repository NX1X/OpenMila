// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Upstream's `VoiceMemosLibrary` reads the SQLite database of Apple's Voice
// Memos app, which only exists on a Mac signed in to iCloud. OpenMila adapts
// the feature to "watched folders": any folder the user syncs recordings into
// (Syncthing, Nextcloud, iCloud Drive for Windows, a phone's USB mount).
//
// The portable settings object still asks this type for the folder to suggest
// in the picker, so that one entry point is provided here. The importer itself
// belongs to the platform layer.

import Foundation

struct VoiceMemosLibrary {
    /// Suggested starting point for the folder picker: the user's Music
    /// folder when it exists, otherwise their home directory.
    static var defaultRecordingsDirectory: URL {
        let fm = FileManager.default
        if let music = fm.urls(for: .musicDirectory, in: .userDomainMask).first,
           fm.fileExists(atPath: music.path) {
            return music
        }
        return fm.homeDirectoryForCurrentUser
    }
}
