import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Settings.soundKey) private var soundName = Notifier.chime
    @AppStorage(Settings.soundEnabledKey) private var soundEnabled = true
    @AppStorage(Settings.notifyKey) private var notificationsEnabled = true
    @AppStorage(Settings.menuBarModeKey) private var menuBarMode = MenuBarMode.tasks.rawValue
    @AppStorage(Settings.limitAlertsKey) private var limitAlerts = true
    @AppStorage(Settings.limitThresholdKey) private var limitThreshold = 80
    @AppStorage(Settings.resetPingKey) private var resetPing = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var previewBounce = 0
    @EnvironmentObject var display: DisplayModeController
    @ObservedObject private var pomodoro = AppModels.pomodoro.timer
    @ObservedObject private var registry = AppModels.registry
    @AppStorage(PomodoroTimer.Keys.sound) private var pomodoroSound = true
    @AppStorage(PomodoroTimer.Keys.haptic) private var pomodoroHaptic = true
    @AppStorage(PomodoroTimer.Keys.musicSync) private var pomodoroMusicSync = false
    @AppStorage(MusicModule.Keys.popOnChange) private var musicPop = true
    @AppStorage(MusicModule.Keys.listOnHover) private var musicListOnHover = true
    @AppStorage(MotionPreference.forceKey) private var forceReduceMotion = false
    @AppStorage(NotchWindowController.openOnHoverKey) private var openOnHover = true
    @AppStorage("settingsTab") private var settingsTab = 0

    var body: some View {
        VStack(spacing: 12) {
            SettingsTabs(selection: $settingsTab)
            switch settingsTab {
            case 1:
                ModulesSettings(registry: AppModels.registry)
            case 2:
                section("Pomodoro", symbol: "flame.fill", color: Palette.silver) {
                    row("Focus") { minutes($pomodoro.focusMinutes, 5...120, step: 5) }
                    row("Short break") { minutes($pomodoro.shortBreakMinutes, 1...30, step: 1) }
                    row("Long break (every 4)") { minutes($pomodoro.longBreakMinutes, 5...60, step: 5) }
                    row("Sound when a phase ends") { toggle($pomodoroSound) }
                    row("Haptic when a phase ends") { toggle($pomodoroHaptic) }
                    row("Play music while focusing, pause for breaks") { toggle($pomodoroMusicSync) }
                }
            case 3:
                section("Music", symbol: "music.note", color: Palette.silver) {
                    row("Pop up when the song changes") { toggle($musicPop) }
                    row("Show the playlist on hover") { toggle($musicListOnHover) }
                }
            case 4:
                section("When Claude finishes", symbol: "bell.fill", color: Palette.silver) {
                    row("Play a sound") { toggle($soundEnabled) }
                    row("Sound") {
                        HStack(spacing: 6) {
                            Picker("", selection: $soundName) {
                                ForEach(Notifier.allSounds, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                            .onChange(of: soundName) { _, name in Notifier.shared.playSound(name) }
                            Button {
                                previewBounce += 1
                                Notifier.shared.playSound(soundName)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(Palette.silver)
                                    .symbolEffect(.variableColor.iterative, options: .nonRepeating, value: previewBounce)
                            }
                            .buttonStyle(.plain)
                            .help("Preview")
                        }
                        .disabled(!soundEnabled)
                        .opacity(soundEnabled ? 1 : 0.4)
                    }
                    row("Show a notification") { toggle($notificationsEnabled) }
                }
                section("Limit alerts", symbol: "gauge.with.dots.needle.67percent", color: Palette.silver) {
                    row("Warn me near the limit") { toggle($limitAlerts) }
                    row("At") {
                        Picker("", selection: $limitThreshold) {
                            ForEach([70, 80, 90, 95], id: \.self) { Text("\($0)%").tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .disabled(!limitAlerts && !resetPing)
                    .opacity(limitAlerts || resetPing ? 1 : 0.4)
                    row("Ping when the session limit resets") { toggle($resetPing) }
                }
            case 5:
                section("Calendar", symbol: "calendar", color: Palette.silver) {
                    row("Show the next calendar event") {
                        toggle(Binding(get: { registry.isEnabled("info") }, set: { registry.setEnabled("info", $0) }))
                    }
                }
                section("System", symbol: "power.circle.fill", color: Palette.silver) {
                    row("Open at login") {
                        toggle($launchAtLogin)
                            .onChange(of: launchAtLogin) { _, enabled in
                                do {
                                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                                    loginError = nil
                                } catch {
                                    loginError = "Move the app to /Applications first, then try again."
                                }
                            }
                    }
                    row("Always reduce motion") { toggle($forceReduceMotion) }
                    if let loginError {
                        Text(loginError).font(.app(11)).foregroundStyle(Palette.rose).padding(.bottom, 8)
                    }
                    row("Quit \(AppInfo.name)") {
                        Button("Quit") { NSApp.terminate(nil) }
                            .controlSize(.small)
                    }
                }
                Text("Token counts come from Claude Code's local history. Plan limits use the same unofficial endpoint as /usage, so they may stop working if Anthropic changes it.")
                    .font(.app(11))
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            default:
                section("Display", symbol: "macbook", color: Palette.silver) {
                    row("Show the app in") {
                        Picker("", selection: $display.setting) {
                            ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    row("Open when the pointer rests on it") { toggle($openOnHover) }
                    Text("Auto uses the notch on the screen with the menu bar, drawing one on an external monitor. All screens puts a notch on every display.")
                        .font(.app(11))
                        .foregroundStyle(Palette.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 6)
                }
                section("Menu bar", symbol: "menubar.rectangle", color: Palette.silver) {
                    row("Next to the icon") {
                        Picker("", selection: $menuBarMode) {
                            ForEach(MenuBarMode.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, symbol: String, color: Color,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Palette.glass))
                    .overlay(Circle().strokeBorder(Palette.line, lineWidth: 1))
                Text(title.uppercased())
                    .font(.app(10.5, .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Palette.text2)
            }
            .padding(.bottom, 4)
            content()
        }
        .card()
    }

    private func row<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label).font(.app(12.5)).foregroundStyle(Palette.text)
            Spacer()
            control()
        }
        .frame(minHeight: 32)
    }

    private func minutes(_ binding: Binding<Int>, _ range: ClosedRange<Int>, step: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(binding.wrappedValue) min")
                .font(.app(12))
                .foregroundStyle(Palette.text2)
                .monospacedDigit()
            Stepper("", value: binding, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private func toggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding).toggleStyle(.switch).controlSize(.mini).tint(Palette.steel).labelsHidden()
    }
}

/// Six small tabs across the top of Settings.
private struct SettingsTabs: View {
    @Binding var selection: Int
    private let tabs: [(String, String)] = [("Display", "macbook"), ("Modules", "square.grid.2x2"), ("Pomodoro", "flame"),
                                            ("Music", "music.note"), ("Claude", "sparkle"), ("System", "gearshape")]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs.indices, id: \.self) { i in
                VStack(spacing: 3) {
                    Image(systemName: tabs[i].1).font(.system(size: 11, weight: .medium))
                    Text(tabs[i].0).font(.app(9, .medium)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .foregroundStyle(selection == i ? Palette.onSilver : Palette.text2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    if selection == i { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.silverGradient) }
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(Motion.smooth) { selection = i } }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.glass))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.rim, lineWidth: 1))
    }
}

/// Turn modules on and off, and drag them into the order they should win the live notch.
private struct ModulesSettings: View {
    @ObservedObject var registry: ModuleRegistry
    @State private var dragging: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("Modules") {
                if registry.customOrder != nil {
                    Button("Reset order") { registry.setOrder(nil) }
                        .buttonStyle(.plain)
                        .font(.app(10.5, .medium))
                        .foregroundStyle(Palette.text2)
                }
            }
            Text("Drag to choose which module wins the live notch when several are active.")
                .font(.app(11))
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            ForEach(registry.orderedIDs, id: \.self) { id in
                row(id)
                    .opacity(dragging == id ? 0.4 : 1)
                    .draggable(id) {
                        Text(ModuleRegistry.title(for: id)).font(.app(12, .medium)).padding(6)
                            .onAppear { dragging = id }
                    }
                    .dropDestination(for: String.self) { items, _ in
                        dragging = nil
                        guard let moved = items.first, moved != id else { return false }
                        var order = registry.orderedIDs
                        order.removeAll { $0 == moved }
                        order.insert(moved, at: order.firstIndex(of: id) ?? order.endIndex)
                        withAnimation(Motion.smooth) { registry.setOrder(order) }
                        return true
                    }
            }
            Text("Info (the next calendar event) lives in the header and never takes the live notch.")
                .font(.app(10.5))
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .card()
    }

    private func row(_ id: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.text3)
            Text(ModuleRegistry.title(for: id))
                .font(.app(12.5))
                .foregroundStyle(Palette.text)
            Spacer()
            Toggle("", isOn: Binding(get: { registry.isEnabled(id) }, set: { registry.setEnabled(id, $0) }))
                .toggleStyle(.switch).controlSize(.mini).tint(Palette.steel).labelsHidden()
        }
        .frame(minHeight: 30)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.glass))
        .contentShape(Rectangle())
    }
}
