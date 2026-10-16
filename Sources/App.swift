import SwiftUI

@main
struct MacMonitorApp: App {
    @StateObject private var sys = SystemModel()
    @StateObject private var cleaner = CleanerModel()
    @StateObject private var sec = SecurityModel()
    @StateObject private var apps = AppsModel()
    @StateObject private var clutter = ClutterModel()
    @StateObject private var ui = UIModel()
    @StateObject private var lens = SpaceLensModel()
    @StateObject private var timeMachine = TimeMachineModel()
    @StateObject private var leftovers = LeftoversModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(sys: sys, sec: sec, ui: ui, cleaner: cleaner, clutter: clutter)
        } label: {
            let warn = sys.pressureLevel >= 2 ? "⚠︎ " : ""
            Text("\(warn)CPU \(Int(sys.cpu.rounded()))%  RAM \(Int((Double(sys.memUsed) / Double(sys.memTotal) * 100).rounded()))%")
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)

        Window("MacMonitor", id: "main") {
            MainView(sys: sys, cleaner: cleaner, sec: sec, apps: apps, clutter: clutter, ui: ui,
                     lens: lens, timeMachine: timeMachine, leftovers: leftovers)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 700)
    }
}
