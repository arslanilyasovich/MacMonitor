import Foundation

/// Her silme ve Çöp Kutusu'na taşıma işleminden önceki son kontrol.
/// Sebep döndürürse işlem yapılmaz. Kurallar bilerek katı: emin olunamayan her şey reddedilir.
enum Safety {
    // Ev klasöründe asla dokunulmayan yerler: anahtarlar, giriş bilgileri, kullanıcı kitaplıkları, bulut klasörleri
    private static let protectedPrefixes = [
        ".ssh", ".gnupg", ".claude", ".aws/credentials", ".config/gh", ".git",
        "Library/Keychains", "Library/Mail", "Library/Messages", "Library/Safari", "Library/Cookies",
        "Library/Accounts", "Library/Mobile Documents", "Library/CloudStorage",
        "Library/Application Support/Claude", "Library/Application Support/com.apple.TCC",
        "Library/Application Support/AddressBook", "Library/Calendars", "Library/Notes",
    ]
    private static let gitPaths = ["/Library/Developer/CommandLineTools/usr/bin/git",
                                   "/Applications/Xcode.app/Contents/Developer/usr/bin/git"]

    /// gitCheck: otomatik bulunan öğelerde (önbellek, proje artığı) git'in takip ettiği dosyalara dokunma.
    /// Kullanıcının kendi seçtiği dosyalarda (Alan Haritası, büyük dosyalar) kapalıdır.
    static func refusal(_ url: URL, gitCheck: Bool = false) -> String? {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(home.path + "/") else { return t("Ev klasörünün dışında", "Outside your home folder") }
        let rel = String(path.dropFirst(home.path.count + 1))
        let parts = rel.split(separator: "/").map(String.init)

        // ~/Desktop, ~/Library gibi ana klasörlerin kendisi asla
        if parts.count < 2 { return t("Ana klasör korunuyor", "Top-level folder is protected") }
        if protectedPrefixes.contains(where: { rel == $0 || rel.hasPrefix($0 + "/") }) {
            return t("Korunan konum", "Protected location")
        }
        if parts.contains(".git") { return t("Git geçmişi korunuyor", "Git history is protected") }
        if parts.contains(where: { $0.hasSuffix(".photoslibrary") }) { return t("Fotoğraf arşivi korunuyor", "Photo library is protected") }
        if let name = parts.last, name == ".env" || name.hasPrefix(".env.") { return t("Ayar dosyası korunuyor", "Config file is protected") }

        // Kısayol ya da kısayol üzerinden giden yol: asıl hedef bambaşka bir yerde olabilir
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            return t("Kısayol (symlink)", "Symbolic link")
        }
        let parent = url.deletingLastPathComponent().standardizedFileURL
        if parent.resolvingSymlinksInPath().path != parent.path { return t("Kısayol üzerinden giden yol", "Path goes through a symbolic link") }

        if gitCheck, let why = gitRefusal(url, path: path) { return why }
        return nil
    }

    /// Git deposundaysa: deponun kendisi olmamalı ve .gitignore'da olmalı. Yani kaynak kod asla.
    private static func gitRefusal(_ url: URL, path: String) -> String? {
        var dir = url.deletingLastPathComponent()
        while dir.path.hasPrefix(home.path + "/") {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
            return t("Git deposunun kendisi", "A git repository itself")
        }
        guard dir.path.hasPrefix(home.path + "/") else { return nil } // depo içinde değil
        guard let git = gitPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return t("Git yok, depo içi kontrol edilemedi", "Git missing, can't verify repository contents")
        }
        let rel = String(path.dropFirst(dir.path.count + 1))
        return runStatus(git, ["-C", dir.path, "check-ignore", "-q", "--", rel]) == 0
            ? nil : t("Git'te takip edilen dosya", "Tracked by git")
    }
}

/// Komutu çalıştırıp sadece çıkış kodunu döndürür (-1: çalıştırılamadı).
func runStatus(_ path: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

/// Kök diskteki gerçekten boş alan (Çöp Kutusu'na taşımak bunu değiştirmez, kalıcı silmek değiştirir).
func volumeFreeBytes() -> Int64 {
    var s = statfs()
    guard statfs("/", &s) == 0 else { return 0 }
    return Int64(s.f_bavail) * Int64(s.f_bsize)
}
