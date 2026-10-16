import SwiftUI
import AppKit

let home = FileManager.default.homeDirectoryForCurrentUser

// MARK: - Dil (Türkçe / English)

final class Lang: ObservableObject {
    static let shared = Lang()

    @Published var code: String {
        didSet { UserDefaults.standard.set(code, forKey: "lang") }
    }

    var isEnglish: Bool { code == "en" }

    private init() {
        code = UserDefaults.standard.string(forKey: "lang")
            ?? (Locale.preferredLanguages.first?.hasPrefix("tr") == true ? "tr" : "en")
    }
}

/// Seçili dile göre Türkçe veya İngilizce metni döndürür.
func t(_ tr: String, _ en: String) -> String { Lang.shared.isEnglish ? en : tr }

struct LanguagePicker: View {
    @ObservedObject var lang = Lang.shared

    var body: some View {
        Picker("", selection: $lang.code) {
            Text("Türkçe").tag("tr")
            Text("English").tag("en")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

// MARK: - Biçimlendirme

private let byteFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowsNonnumericFormatting = false // "Zero KB" yerine "0 bayt"
    return f
}()

func fmtBytes(_ b: Int64) -> String { b <= 0 ? "0 KB" : byteFormatter.string(fromByteCount: b) }
func fmtBytes(_ b: UInt64) -> String { fmtBytes(Int64(clamping: b)) }

func speed(_ bps: Double) -> String {
    let unit = t("sn", "s")
    switch bps {
    case ..<1_000: return String(format: "%.0f B/%@", bps, unit)
    case ..<1_000_000: return String(format: "%.0f KB/%@", bps / 1_000, unit)
    default: return String(format: "%.1f MB/%@", bps / 1_000_000, unit)
    }
}

func duration(_ t0: TimeInterval) -> String {
    let s = Int(t0)
    let d = s / 86_400, h = s % 86_400 / 3_600, m = s % 3_600 / 60
    if d > 0 { return t("\(d) g \(h) sa", "\(d)d \(h)h") }
    if h > 0 { return t("\(h) sa \(m) dk", "\(h)h \(m)m") }
    return t("\(m) dk", "\(m)m")
}

func ago(_ date: Date?) -> String {
    guard let date else { return t("henüz yapılmadı", "not yet") }
    let s = -date.timeIntervalSinceNow
    if s < 60 { return t("az önce", "just now") }
    if s < 3_600 { return t("\(Int(s / 60)) dk önce", "\(Int(s / 60)) min ago") }
    if s < 86_400 { return t("\(Int(s / 3_600)) sa önce", "\(Int(s / 3_600)) h ago") }
    return t("\(Int(s / 86_400)) gün önce", "\(Int(s / 86_400)) days ago")
}

// MARK: - Komut çalıştırma

@discardableResult
func runCommand(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

/// Yönetici şifresi isteyen standart macOS penceresiyle bir kabuk komutu çalıştırır.
@discardableResult
func runAdmin(_ shell: String, prompt: String) -> Bool {
    let esc = { (s: String) in s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
    return runAppleScript("do shell script \"\(esc(shell))\" with administrator privileges with prompt \"\(esc(prompt))\"")
}

@discardableResult
func runAppleScript(_ source: String) -> Bool {
    var err: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&err)
    return err == nil
}

func openSettings(_ url: String) {
    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
}

func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

func sizeOf(_ url: URL) -> Int64 {
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
    guard let v = try? url.resourceValues(forKeys: keys) else { return 0 }
    if v.isDirectory != true { return Int64(v.totalFileAllocatedSize ?? 0) }
    var total: Int64 = 0
    if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) {
        for case let f as URL in e {
            total += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
    }
    return total
}

// MARK: - Tema: logodaki koyu lacivert zemin ve elektrik mavisi

enum Theme {
    static let bgTop = Color(red: 0.03, green: 0.05, blue: 0.10)
    static let bgBottom = Color(red: 0.04, green: 0.07, blue: 0.15)
    static let card = Color.white.opacity(0.045)
    static let stroke = Color.white.opacity(0.08)
    static let secondary = Color.white.opacity(0.58)
    static let accent = Color(red: 0.27, green: 0.64, blue: 1.0)      // logodaki "Monitor" mavisi
    static let accent2 = Color(red: 0.12, green: 0.40, blue: 0.96)    // koyu mavi
    static let good = Color(red: 0.36, green: 0.90, blue: 0.58)
    static let warn = Color(red: 1.0, green: 0.74, blue: 0.30)
    static let bad = Color(red: 1.0, green: 0.42, blue: 0.40)
    static let sidebar = Color.black.opacity(0.35)
}

/// Koyu lacivert zemin + köşelerde logodaki gibi mavi parıltı
struct ThemeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.accent2.opacity(0.22), .clear], center: .topTrailing, startRadius: 10, endRadius: 560)
            RadialGradient(colors: [Theme.accent.opacity(0.10), .clear], center: .bottomLeading, startRadius: 10, endRadius: 460)
        }
    }
}

// MARK: - Ortak bileşenler

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }
}

struct LinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
        }.buttonStyle(.plain)
    }
}

struct PrimaryButton: View {
    let title: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(Capsule().fill(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .leading, endPoint: .trailing)))
                .shadow(color: Theme.accent.opacity(0.35), radius: 8)
                .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct SecondaryButton: View {
    let title: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct BigRoundButton: View {
    let title: String
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Theme.accent.opacity(0.55), radius: 26)
                Circle().stroke(Color.white.opacity(0.3), lineWidth: 2)
                if busy {
                    ProgressView().controlSize(.regular)
                } else {
                    Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: 100, height: 100)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

/// "prod. by Arslan" imzası
struct Signature: View {
    var size: CGFloat = 11

    var body: some View {
        (Text("prod. by ").foregroundColor(Theme.secondary) + Text("Arslan").foregroundColor(Theme.accent).fontWeight(.semibold))
            .font(.system(size: size, design: .rounded))
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 26, weight: .bold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppIcon: View {
    let path: String
    var size: CGFloat = 24

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .frame(width: size, height: size)
    }
}

struct Donut: View {
    let segments: [(Double, Color)]
    var lineWidth: CGFloat = 22

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.06), lineWidth: lineWidth)
            ForEach(Array(segments.enumerated()), id: \.offset) { i, seg in
                let start = segments.prefix(i).reduce(0) { $0 + $1.0 }
                Circle()
                    .trim(from: start, to: min(start + seg.0, 1))
                    .stroke(seg.1, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: seg.1.opacity(0.45), radius: 8)
            }
        }
    }
}

struct BackHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: back) {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.card))
            }.buttonStyle(.plain)
            Text(title).font(.system(size: 22, weight: .bold))
            Spacer()
        }
    }
}
