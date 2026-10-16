import SwiftUI
import AppKit
import Darwin
import IOKit
import IOKit.ps

struct ProcRow: Identifiable {
    let id: String
    let name: String
    let bytes: UInt64
    let pids: [pid_t]
    let appPath: String?
    let iconPath: String
    let quittable: Bool
    var cpu: Double = 0
    var count: Int { pids.count }
}

struct DiskPart: Identifiable {
    var id: String { key }
    let key: String
    let bytes: Int64?
    let color: Color

    var title: String {
        switch key {
        case "documents": return t("Belgeler", "Documents")
        case "applications": return t("Uygulamalar", "Applications")
        case "desktop": return t("Masaüstü", "Desktop")
        case "downloads": return t("İndirilenler", "Downloads")
        default: return t("Diğer", "Other")
        }
    }
}

struct BatteryDetail {
    let cycles: Int?
    let healthPercent: Int?
    let temperature: Double?
}

struct BTDevice: Identifiable {
    var id: String { name }
    let name: String
    let battery: String?
    let symbol: String
}

struct BatteryInfo {
    let percent: Int
    let charging: Bool
    let minutesLeft: Int?
}

/// CPU, bellek, ağ, disk, pil ve Bluetooth ölçümleri.
final class SystemModel: ObservableObject {
    static let agentLabel = "local.a26.macmonitor"
    static let agentURL = home.appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")

    @Published var cpu: Double = 0
    @Published var memApp: UInt64 = 0
    @Published var memWired: UInt64 = 0
    @Published var memCompressed: UInt64 = 0
    let memTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    var memUsed: UInt64 { memApp + memWired + memCompressed }
    var memFree: UInt64 { memTotal > memUsed ? memTotal - memUsed : 0 }
    @Published var swapUsed: UInt64 = 0
    @Published var pressureLevel = 1
    @Published var pressurePercent = 0
    @Published var netDown: Double = 0
    @Published var netUp: Double = 0
    @Published var netPort = ""          // donanım bağlantı adı (örn. "Ethernet")
    @Published var netKind = "none"      // none, vpn, wifi, wired
    @Published var netSymbol = "network"
    var netName: String {
        switch netKind {
        case "vpn": return "VPN"
        case "wifi": return "Wi‑Fi"
        case "wired": return netPort
        default: return t("Ağ", "Network")
        }
    }
    @Published var diskFree: Int64 = 0
    @Published var diskTotal: Int64 = 0
    @Published var diskName = "Macintosh HD"
    @Published var top: [ProcRow] = []
    @Published var pendingQuit: String?
    @Published var uptime: TimeInterval = 0
    @Published var machineName = "Mac"
    @Published var machineSymbol = "desktopcomputer"
    @Published var battery: BatteryInfo?
    @Published var devices: [BTDevice] = []
    @Published var speedTesting = false
    @Published var speedResult: String?
    @Published var maintenanceRunning = false
    @Published var maintenanceResult: String?
    @Published var cpuUser: Double = 0
    @Published var cpuSystem: Double = 0
    @Published var cpuHistory: [Double] = []
    @Published var topCPU: [ProcRow] = []
    @Published var chipName = ""
    @Published var netDownHistory: [Double] = []
    @Published var netUpHistory: [Double] = []
    @Published var netTotalDown: UInt64 = 0
    @Published var netTotalUp: UInt64 = 0
    @Published var speedDownMbps: Double?
    @Published var speedUpMbps: Double?
    @Published var speedRPM: Int?
    @Published var diskParts: [DiskPart] = []
    @Published var diskSmart: String?
    @Published var trashSize: Int64?
    @Published var diskDetailsLoading = false
    @Published var batteryDetail: BatteryDetail?
    @Published var launchAtLogin = FileManager.default.fileExists(atPath: SystemModel.agentURL.path) {
        didSet { setLoginAgent(launchAtLogin) }
    }

    private var prevTicks: (UInt64, UInt64, UInt64)?
    private var prevProcCPU: [pid_t: UInt64] = [:]
    private var prevProcTime: UInt64 = 0
    private var diskDetailsAt: Date?
    private static let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()
    private var prevNet: (UInt64, UInt64, Date)?
    private var timer: Timer?
    private var slowTimer: Timer?
    private var tick = 0

    private static let protectedNames: Set<String> = [
        "Finder", "Dock", "loginwindow", "SystemUIServer", "ControlCenter", "WindowManager",
        "NotificationCenter", "Spotlight", "MacMonitor",
    ]

    init() {
        // İlk açılışta otomatik başlatmayı aç (sonra kullanıcı Ayarlar'dan kapatabilir)
        if !UserDefaults.standard.bool(forKey: "didFirstRun") {
            UserDefaults.standard.set(true, forKey: "didFirstRun")
            launchAtLogin = true
            setLoginAgent(true)
        }
        refresh()
        readMachine()
        readSlow()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        slowTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.readSlow() }
    }

    func refresh() {
        readCPU()
        readMemory()
        readNetwork()
        if tick % 2 == 0 { readTopProcesses() }
        if tick % 5 == 0 { readDisk(); readUptime() }
        if tick % 15 == 0 { readBattery() }
        tick += 1
    }

    // MARK: Eylemler

    private func setLoginAgent(_ on: Bool) {
        let url = SystemModel.agentURL
        if on {
            let plist: [String: Any] = [
                "Label": SystemModel.agentLabel,
                "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath], // nereye kurulduysa oradan aç
                "RunAtLoad": true,
            ]
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url)
            }
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// İlk tıklama onay ister ("Emin misin?"), 3 sn içinde ikinci tıklama kapatır.
    func quit(_ p: ProcRow) {
        guard pendingQuit == p.id else {
            pendingQuit = p.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                if self?.pendingQuit == p.id { self?.pendingQuit = nil }
            }
            return
        }
        pendingQuit = nil
        if let path = p.appPath {
            let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == path }
            if !apps.isEmpty {
                apps.forEach { $0.terminate() }
                return
            }
        }
        p.pids.forEach { kill($0, SIGTERM) }
    }

    func runSpeedTest() {
        guard !speedTesting else { return }
        speedTesting = true
        speedResult = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let out = runCommand("/usr/bin/networkQuality", ["-c"])
            var result = t("Ölçülemedi", "Couldn't measure")
            if let data = out.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dl = json["dl_throughput"] as? Double, let ul = json["ul_throughput"] as? Double {
                result = String(format: "↓ %.0f Mbps   ↑ %.0f Mbps", dl / 1_000_000, ul / 1_000_000)
                let rpm = (json["responsiveness"] as? Double).map { Int($0) }
                DispatchQueue.main.async {
                    self.speedDownMbps = dl / 1_000_000
                    self.speedUpMbps = ul / 1_000_000
                    self.speedRPM = rpm
                }
            }
            DispatchQueue.main.async {
                self.speedResult = result
                self.speedTesting = false
            }
        }
    }

    func runMaintenance(_ tasks: Set<String>) {
        var cmds: [String] = []
        if tasks.contains("purge") { cmds.append("/usr/sbin/purge") }
        if tasks.contains("dns") { cmds.append("/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder") }
        if tasks.contains("spotlight") { cmds.append("/usr/bin/mdutil -E /") }
        guard !cmds.isEmpty, !maintenanceRunning else { return }
        maintenanceRunning = true
        maintenanceResult = nil
        DispatchQueue.main.async {
            let ok = runAdmin(cmds.joined(separator: "; "), prompt: t("MacMonitor bakım görevlerini çalıştıracak.", "MacMonitor will run maintenance tasks."))
            self.maintenanceRunning = false
            self.maintenanceResult = ok ? t("✓ Bakım görevleri tamamlandı", "✓ Maintenance tasks finished") : t("İptal edildi veya başarısız oldu", "Cancelled or failed")
        }
    }

    // MARK: Ölçümler

    private func readCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let ticks = info.cpu_ticks
        let user = UInt64(ticks.0) + UInt64(ticks.3)   // user + nice
        let system = UInt64(ticks.1)
        let total = user + system + UInt64(ticks.2)
        if let (pu, ps, pt) = prevTicks, total > pt {
            let dt = Double(total - pt)
            cpuUser = Double(user - pu) / dt * 100
            cpuSystem = Double(system - ps) / dt * 100
            cpu = cpuUser + cpuSystem
            cpuHistory = Array((cpuHistory + [cpu]).suffix(60))
        }
        prevTicks = (user, system, total)
    }

    private func readMemory() {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)
        // Etkinlik Monitörü ile aynı ayrım: uygulama belleği + sabit (wired) + sıkıştırılmış
        memApp = (UInt64(vm.internal_page_count) - UInt64(vm.purgeable_count)) * page
        memWired = UInt64(vm.wire_count) * page
        memCompressed = UInt64(vm.compressor_page_count) * page

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { swapUsed = swap.xsu_used }

        var level: Int32 = 1
        size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 { pressureLevel = Int(level) }

        // memory_pressure komutunun gösterdiği "boş yüzde"nin tersi
        var freePct: Int32 = 100
        size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_level", &freePct, &size, nil, 0) == 0 { pressurePercent = max(0, 100 - Int(freePct)) }
    }

    private func readNetwork() {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return }

        var down: UInt64 = 0, up: UInt64 = 0
        buf.withUnsafeBytes { raw in
            var off = 0
            while off + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr.self)
                if Int32(hdr.ifm_type) == RTM_IFINFO2 {
                    let h2 = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr2.self)
                    var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if let n = if_indextoname(UInt32(h2.ifm_index), &nameBuf), String(cString: n).hasPrefix("en") {
                        // Sadece fiziksel arayüzler: VPN tüneli (utun) aynı trafiği ikinci kez saydırmasın
                        down += h2.ifm_data.ifi_ibytes
                        up += h2.ifm_data.ifi_obytes
                    }
                }
                guard hdr.ifm_msglen > 0 else { break }
                off += Int(hdr.ifm_msglen)
            }
        }
        let now = Date()
        if let (pd, pu, pt) = prevNet, down >= pd, up >= pu {
            let dt = now.timeIntervalSince(pt)
            if dt > 0 {
                netDown = Double(down - pd) / dt
                netUp = Double(up - pu) / dt
                netDownHistory = Array((netDownHistory + [netDown]).suffix(60))
                netUpHistory = Array((netUpHistory + [netUp]).suffix(60))
            }
        }
        netTotalDown = down
        netTotalUp = up
        prevNet = (down, up, now)
    }

    private func readDisk() {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey]
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) {
            diskTotal = Int64(v.volumeTotalCapacity ?? 0)
            diskFree = v.volumeAvailableCapacityForImportantUsage ?? 0
            diskName = v.volumeLocalizedName ?? "Macintosh HD"
        }
    }

    private func readUptime() {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 {
            uptime = Date().timeIntervalSince1970 - Double(tv.tv_sec)
        }
    }

    private func readBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [AnyObject] else {
            battery = nil
            return
        }
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let tte = d[kIOPSTimeToEmptyKey] as? Int ?? -1
            battery = BatteryInfo(percent: d[kIOPSCurrentCapacityKey] as? Int ?? 0,
                                  charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                                  minutesLeft: tte > 0 ? tte : nil)
            batteryDetail = Self.readBatteryDetail()
            return
        }
        battery = nil
    }

    /// Döngü sayısı, sağlık ve sıcaklık: AppleSmartBattery kaydından okunur (sadece dizüstülerde var)
    static func readBatteryDetail() -> BatteryDetail? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        func prop(_ key: String) -> Int? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        }
        let design = prop("DesignCapacity")
        let maxCap = prop("AppleRawMaxCapacity") ?? prop("NominalChargeCapacity")
        let health = (design ?? 0) > 0 && maxCap != nil ? min(100, maxCap! * 100 / design!) : nil
        return BatteryDetail(cycles: prop("CycleCount"), healthPercent: health,
                             temperature: prop("Temperature").map { Double($0) / 100 })
    }

    /// Disk sayfası için: klasör boyutları, SMART durumu, Çöp Kutusu boyutu (5 dakikada bir yeniden hesaplanır)
    func loadDiskDetails() {
        if diskDetailsLoading { return }
        if let at = diskDetailsAt, -at.timeIntervalSinceNow < 300 { return }
        diskDetailsLoading = true
        let colors: [String: Color] = ["documents": Theme.accent2, "applications": Theme.bad, "desktop": Theme.good,
                                       "downloads": Color(red: 0.85, green: 0.45, blue: 1.0), "other": Color.white.opacity(0.7)]
        let keys = ["documents", "applications", "desktop", "downloads", "other"]
        if diskParts.isEmpty { diskParts = keys.map { DiskPart(key: $0, bytes: nil, color: colors[$0]!) } }
        let used = diskTotal - diskFree
        DispatchQueue.global(qos: .utility).async {
            let paths = ["documents": home.appendingPathComponent("Documents"),
                         "applications": URL(fileURLWithPath: "/Applications"),
                         "desktop": home.appendingPathComponent("Desktop"),
                         "downloads": home.appendingPathComponent("Downloads")]
            var sizes: [String: Int64] = [:]
            for (k, url) in paths { sizes[k] = sizeOf(url) }
            sizes["other"] = max(0, used - sizes.values.reduce(0, +))
            let smart = runCommand("/usr/sbin/diskutil", ["info", "disk0"]).components(separatedBy: "\n")
                .first { $0.contains("SMART Status") }?
                .components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
            let trashURL = home.appendingPathComponent(".Trash")
            let trash: Int64? = (try? FileManager.default.contentsOfDirectory(atPath: trashURL.path)) != nil ? sizeOf(trashURL) : nil
            DispatchQueue.main.async {
                self.diskParts = keys.map { DiskPart(key: $0, bytes: sizes[$0], color: colors[$0]!) }
                self.diskSmart = smart
                self.trashSize = trash
                self.diskDetailsLoading = false
                self.diskDetailsAt = Date()
            }
        }
    }

    func emptyTrash() {
        if runAppleScript("tell application \"Finder\" to empty trash") {
            trashSize = 0
            diskDetailsAt = nil
        }
    }

    private func readMachine() {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        if sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0) == 0 { chipName = String(cString: buf) }
        DispatchQueue.global(qos: .utility).async {
            let out = runCommand("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"])
            guard let data = out.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hw = (json["SPHardwareDataType"] as? [[String: Any]])?.first,
                  let name = hw["machine_name"] as? String else { return }
            let symbol: String
            switch name {
            case let n where n.contains("mini"): symbol = "macmini"
            case let n where n.contains("MacBook"): symbol = "laptopcomputer"
            case let n where n.contains("Studio"): symbol = "macstudio"
            case let n where n.contains("Pro"): symbol = "macpro.gen3"
            default: symbol = "desktopcomputer"
            }
            DispatchQueue.main.async {
                self.machineName = name
                self.machineSymbol = symbol
            }
        }
    }

    /// Bağlantı türü ve Bluetooth cihazları: yavaş komutlar, dakikada bir arka planda.
    private func readSlow() {
        DispatchQueue.global(qos: .utility).async {
            let route = runCommand("/sbin/route", ["-n", "get", "default"])
            let iface = route.components(separatedBy: "\n")
                .first { $0.contains("interface:") }?
                .components(separatedBy: ":").last?
                .trimmingCharacters(in: .whitespaces) ?? ""
            var kind = "none", port = "", symbol = "network"
            if iface.hasPrefix("utun") || iface.hasPrefix("ipsec") {
                kind = "vpn"; symbol = "lock.shield"
            } else if !iface.isEmpty {
                var current = "", found = ""
                for line in runCommand("/usr/sbin/networksetup", ["-listallhardwareports"]).components(separatedBy: "\n") {
                    if line.hasPrefix("Hardware Port: ") {
                        current = String(line.dropFirst("Hardware Port: ".count))
                    } else if line.trimmingCharacters(in: .whitespaces) == "Device: \(iface)" {
                        found = current
                        break
                    }
                }
                if found.lowercased().contains("wi-fi") { kind = "wifi"; symbol = "wifi" }
                else if !found.isEmpty { kind = "wired"; port = found; symbol = "cable.connector" }
            }
            let devices = Self.readBluetooth()
            DispatchQueue.main.async {
                self.netKind = kind
                self.netPort = port
                self.netSymbol = symbol
                self.devices = devices
            }
        }
    }

    static func readBluetooth() -> [BTDevice] {
        let out = runCommand("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])
        guard let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var result: [BTDevice] = []
        for ctrl in controllers {
            guard let connected = ctrl["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    let d = value as? [String: Any] ?? [:]
                    let battery = (d["device_batteryLevelMain"] ?? d["device_batteryLevelLeft"]
                        ?? d["device_batteryLevelCase"] ?? d["device_batteryLevel"]) as? String
                    let type = ((d["device_minorType"] as? String) ?? "").lowercased()
                    let symbol: String
                    if type.contains("headphone") || type.contains("headset") { symbol = "airpodspro" }
                    else if type.contains("keyboard") { symbol = "keyboard" }
                    else if type.contains("mouse") { symbol = "computermouse" }
                    else if type.contains("trackpad") { symbol = "hand.point.up.left" }
                    else if type.contains("speaker") { symbol = "hifispeaker" }
                    else { symbol = "dot.radiowaves.left.and.right" }
                    result.append(BTDevice(name: name, battery: battery, symbol: symbol))
                }
            }
        }
        return result
    }

    private func readTopProcesses() {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard got > 0 else { return }

        struct Group { var bytes: UInt64 = 0; var cpuDelta: UInt64 = 0; var pids: [pid_t] = []; var appPath: String?; var exePath = ""; var system = false }
        var curCPU: [pid_t: UInt64] = [:]
        var groups: [String: Group] = [:]
        var pathBuf = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(Int(got)) where pid > 0 {
            var ri = rusage_info_v4()
            let r = withUnsafeMutablePointer(to: &ri) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard r == 0, ri.ri_phys_footprint > 0 else { continue }
            guard proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 else { continue }
            let path = String(cString: pathBuf)
            let (name, appPath) = Self.identify(path)
            var g = groups[name] ?? Group()
            g.bytes += ri.ri_phys_footprint
            let cpuTime = ri.ri_user_time + ri.ri_system_time
            curCPU[pid] = cpuTime
            if let prev = prevProcCPU[pid], cpuTime >= prev { g.cpuDelta += cpuTime - prev }
            g.pids.append(pid)
            g.appPath = appPath
            g.exePath = path
            if ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/"].contains(where: path.hasPrefix) { g.system = true }
            groups[name] = g
        }
        let me = getpid()
        // CPU süreleri mach zaman biriminde: nanosaniyeye çevirip geçen süreye böl (Etkinlik Monitörü gibi %100'ü aşabilir)
        let now = mach_absolute_time()
        let elapsed = prevProcTime > 0 ? Double(now - prevProcTime) : 0
        let rows = groups.map { name, g in
            ProcRow(id: name, name: name, bytes: g.bytes, pids: g.pids, appPath: g.appPath,
                    iconPath: g.appPath ?? g.exePath,
                    quittable: !g.system && !Self.protectedNames.contains(name) && !g.pids.contains(me),
                    cpu: elapsed > 0 ? Double(g.cpuDelta) / elapsed * 100 : 0)
        }
        prevProcCPU = curCPU
        prevProcTime = now
        top = Array(rows.sorted { $0.bytes > $1.bytes }.prefix(6))
        if elapsed > 0 { topCPU = Array(rows.sorted { $0.cpu > $1.cpu }.prefix(6)) }
    }

    // Yardımcı işlemleri ana uygulamanın altında topla (örn. tüm "Brave Browser Helper" → "Brave Browser")
    static func identify(_ path: String) -> (String, String?) {
        if let r = path.range(of: ".app/") {
            let appPath = String(path[..<r.lowerBound]) + ".app"
            return (String((appPath as NSString).lastPathComponent.dropLast(4)), appPath)
        }
        let parts = path.split(separator: "/").map(String.init)
        // ~/.local/share/claude/versions/2.1.301 gibi: dosya adı sürüm numarasıysa aracın adını kullan
        if let last = parts.last, last.allSatisfy({ $0.isNumber || $0 == "." }), parts.count >= 3 {
            let owner = parts[parts.count - 2] == "versions" ? parts[parts.count - 3] : parts[parts.count - 2]
            return (owner == "claude" ? "Claude Code" : owner, nil)
        }
        return ((path as NSString).lastPathComponent, nil)
    }
}
