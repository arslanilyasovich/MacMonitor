import SwiftUI
import Security

struct SecCheck: Identifiable {
    let id: String          // sip, gk, fv, fw, xp
    let ok: Bool
    var extra: String? = nil

    var title: String {
        switch id {
        case "sip": return t("Sistem Bütünlüğü Koruması (SIP)", "System Integrity Protection (SIP)")
        case "gk": return "Gatekeeper"
        case "fv": return t("FileVault disk şifreleme", "FileVault disk encryption")
        case "fw": return t("Güvenlik Duvarı", "Firewall")
        default: return t("XProtect (Apple'ın virüs koruması)", "XProtect (Apple's malware protection)")
        }
    }

    var detail: String {
        switch (id, ok) {
        case ("sip", true): return t("Açık — sistem dosyaları değiştirilemez", "On — system files can't be modified")
        case ("sip", false): return t("Kapalı — sistem dosyaları korumasız", "Off — system files are unprotected")
        case ("gk", true): return t("Açık — sadece doğrulanmış uygulamalar açılır", "On — only verified apps can open")
        case ("gk", false): return t("Kapalı — doğrulanmamış uygulamalar açılabilir", "Off — unverified apps can open")
        case ("fv", true): return t("Açık — disk şifreli", "On — disk is encrypted")
        case ("fv", false): return t("Kapalı — Mac çalınırsa dosyalar okunabilir", "Off — files are readable if the Mac is stolen")
        case ("fw", true): return t("Açık", "On")
        case ("fw", false): return t("Kapalı — internetten gelen bağlantılar engellenmiyor", "Off — incoming connections aren't blocked")
        case ("xp", true): return t("Çalışıyor — imza sürümü \(extra ?? "?")", "Running — definitions version \(extra ?? "?")")
        default: return t("Bulunamadı", "Not found")
        }
    }

    var fixURL: String? {
        switch id {
        case "gk", "fv": return "x-apple.systempreferences:com.apple.preference.security"
        case "fw": return "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall"
        default: return nil
        }
    }
}

struct SignedItem: Identifiable {
    var id: String { kindKey + path }
    let name: String
    let path: String
    let iconPath: String
    let kindKey: String     // user, system, daemon, app
    let rawSigner: String
    let status: String      // ok, empty, missing, adhoc, unverified

    var ok: Bool { status == "ok" || status == "empty" }

    var kind: String {
        switch kindKey {
        case "user": return t("Kullanıcı başlangıç öğesi", "User launch agent")
        case "system": return t("Sistem başlangıç öğesi", "System launch agent")
        case "daemon": return t("Arka plan servisi (root)", "Background daemon (root)")
        default: return t("Uygulama", "App")
        }
    }

    var signer: String {
        switch status {
        case "empty": return t("Boş kayıt — hiçbir şey çalıştırmıyor", "Empty entry — runs nothing")
        case "missing": return rawSigner.isEmpty ? t("Program belirtilmemiş", "No program set") : rawSigner
        default:
            switch rawSigner {
            case "": return t("İmzasız", "Unsigned")
            case "adhoc": return t("Yerel (ad-hoc) imza", "Local (ad-hoc) signature")
            default: return rawSigner
            }
        }
    }

    var note: String {
        switch status {
        case "ok": return t("Doğrulandı", "Verified")
        case "empty": return t("Zararsız", "Harmless")
        case "missing": return t("Programı yok (artık kayıt)", "Program missing (leftover)")
        case "adhoc": return t("Yerel imza — sen mi oluşturdun?", "Local signature — did you build it?")
        default: return t("Apple tarafından doğrulanmamış", "Not verified by Apple")
        }
    }
}

/// macOS güvenlik ayarları + başlangıç öğeleri ve uygulamaların imza kontrolü.
/// Gerçek zamanlı antivirüs değildir: kırık/imzasız yazılımları ve kapalı korumaları bulur.
final class SecurityModel: ObservableObject {
    @Published var checks: [SecCheck] = []
    @Published var items: [SignedItem] = []
    @Published var scanning = false
    @Published var lastScan: Date?

    private var timer: Timer?

    var issueCount: Int { checks.filter { !$0.ok }.count + items.filter { !$0.ok }.count }

    var summary: String {
        if lastScan == nil { return t("İlk kontrol yapılıyor…", "Running first check…") }
        if let c = checks.first(where: { !$0.ok }) { return t("\(c.title) kapalı", "\(c.title) is off") }
        if let i = items.first(where: { !$0.ok }) { return "\(i.name): \(i.note)" }
        return t("Sistem korumaları açık, imzasız yazılım yok", "System protections on, no unsigned software")
    }

    private static let appleRequirement: SecRequirement? = {
        var r: SecRequirement?
        SecRequirementCreateWithString("anchor apple generic" as CFString, [], &r)
        return r
    }()

    init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.scan() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3_600, repeats: true) { [weak self] _ in self?.scan() }
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async {
            let checks = Self.buildChecks()
            let items = Self.scanLaunchItems() + Self.scanApps()
            DispatchQueue.main.async {
                self.checks = checks
                self.items = items
                self.lastScan = Date()
                self.scanning = false
            }
        }
    }

    private static func buildChecks() -> [SecCheck] {
        let xp = NSDictionary(contentsOfFile: "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist")?["CFBundleShortVersionString"] as? String
        return [
            SecCheck(id: "sip", ok: runCommand("/usr/bin/csrutil", ["status"]).contains("enabled")),
            SecCheck(id: "gk", ok: runCommand("/usr/sbin/spctl", ["--status"]).contains("enabled")),
            SecCheck(id: "fv", ok: runCommand("/usr/bin/fdesetup", ["status"]).contains("On")),
            SecCheck(id: "fw", ok: runCommand("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"]).contains("enabled")),
            SecCheck(id: "xp", ok: xp != nil, extra: xp),
        ]
    }

    private static func scanLaunchItems() -> [SignedItem] {
        let dirs: [(String, String)] = [
            (home.appendingPathComponent("Library/LaunchAgents").path, "user"),
            ("/Library/LaunchAgents", "system"),
            ("/Library/LaunchDaemons", "daemon"),
        ]
        var result: [SignedItem] = []
        for (dir, kind) in dirs {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for n in names where n.hasSuffix(".plist") {
                let plistPath = (dir as NSString).appendingPathComponent(n)
                guard let d = NSDictionary(contentsOfFile: plistPath) else { continue }
                let label = d["Label"] as? String ?? String(n.dropLast(6))
                let program = d["Program"] as? String ?? (d["ProgramArguments"] as? [String])?.first ?? ""
                let iconPath = program.range(of: ".app/").map { String(program[..<$0.lowerBound]) + ".app" } ?? program
                // Bazı uygulamalar (örn. Google) kendi servislerini kapatmak için boş kayıt bırakır: çalışmaz, zararsız
                if d.count == 0 || program.isEmpty {
                    result.append(SignedItem(name: label, path: plistPath, iconPath: plistPath, kindKey: kind, rawSigner: "", status: "empty"))
                    continue
                }
                guard FileManager.default.fileExists(atPath: program) else {
                    result.append(SignedItem(name: label, path: plistPath, iconPath: plistPath, kindKey: kind, rawSigner: program, status: "missing"))
                    continue
                }
                let (ok, signer) = checkSignature(program)
                result.append(SignedItem(name: label, path: program, iconPath: iconPath, kindKey: kind, rawSigner: signer,
                                         status: ok ? "ok" : signer == "adhoc" ? "adhoc" : "unverified"))
            }
        }
        return result
    }

    private static func scanApps() -> [SignedItem] {
        var result: [SignedItem] = []
        for dir in ["/Applications", home.appendingPathComponent("Applications").path] {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for n in names where n.hasSuffix(".app") {
                let path = (dir as NSString).appendingPathComponent(n)
                if path == Bundle.main.bundlePath || Bundle(path: path)?.bundleIdentifier == "local.a26.macmonitor" { continue }
                if (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil { continue }
                // App Store'dan kurulan iPhone/iPad uygulamaları bir sarmalayıcı klasörün içindedir
                let wrapped = (path as NSString).appendingPathComponent("WrappedBundle")
                let target = FileManager.default.fileExists(atPath: wrapped) ? wrapped : path
                let (ok, signer) = checkSignature(target)
                result.append(SignedItem(name: String(n.dropLast(4)), path: path, iconPath: path, kindKey: "app", rawSigner: signer,
                                         status: ok ? "ok" : signer == "adhoc" ? "adhoc" : "unverified"))
            }
        }
        return result
    }

    /// İmza Apple'ın sertifika zincirine (Developer ID, App Store veya Apple) bağlı mı?
    /// İkinci değer: sertifika sahibi, "adhoc" ya da imzasızsa "".
    static func checkSignature(_ path: String) -> (Bool, String) {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else {
            return (false, "")
        }
        var info: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        var signer = ""
        if let d = info as? [String: Any] {
            if let certs = d[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certs.first {
                signer = (SecCertificateCopySubjectSummary(leaf) as String?) ?? "?"
                signer = signer.replacingOccurrences(of: "Developer ID Application: ", with: "")
            } else if d[kSecCodeInfoIdentifier as String] != nil {
                signer = "adhoc"
            }
        }
        let valid = SecStaticCodeCheckValidity(code, [], appleRequirement) == errSecSuccess
        return (valid, signer)
    }
}
