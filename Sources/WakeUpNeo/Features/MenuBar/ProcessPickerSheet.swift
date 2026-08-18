import SwiftUI
import AppKit
import WakeUpNeoCore

// MARK: - ProcessPickerSheet

/// Sheet/popover/window allowing the user to select a running application or specify a custom PID to monitor.
struct ProcessPickerSheet: View {

    @Environment(\.dismiss) private var dismiss

    let onSelect: (MonitoredProcessInfo) -> Void
    var onCancel: (() -> Void)? = nil

    @State private var searchText = ""
    @State private var runningApps: [MonitoredProcessInfo] = []
    @State private var customPIDInput = ""
    @State private var customProcessName = ""
    @State private var customPIDError: String?

    private let processService = DefaultProcessWatchingService()

    private var filteredApps: [MonitoredProcessInfo] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return runningApps
        }
        let query = searchText.lowercased()
        return runningApps.filter { app in
            app.name.lowercased().contains(query) ||
            String(app.pid).contains(query) ||
            (app.bundleIdentifier?.lowercased().contains(query) ?? false)
        }
    }

    private var parsedCustomPID: Int32? {
        Int32(customPIDInput.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Watch Application or Process")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onCancel?()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search running apps or enter PID…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            // List of running applications
            List {
                if !filteredApps.isEmpty {
                    Section("Running Applications") {
                        ForEach(filteredApps) { app in
                            appRow(app)
                        }
                    }
                } else if !searchText.isEmpty {
                    Text("No matching running applications found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }

                // Custom PID Entry Section
                Section("Custom Process ID (PID)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Monitor background tasks, CLI tools, or daemons by PID:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField("PID (e.g. 1234)", text: $customPIDInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)

                            TextField("Name (optional)", text: $customProcessName)
                                .textFieldStyle(.roundedBorder)

                            Button("Watch PID") {
                                submitCustomPID()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(parsedCustomPID == nil)
                        }

                        if let error = customPIDError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
            .frame(height: 280)

            // Footer info
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("WakeUpNeo will keep your Mac awake until the selected process exits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 440)
        .onAppear {
            loadRunningApps()
        }
    }

    // MARK: - Rows & Actions

    @ViewBuilder
    private func appRow(_ app: MonitoredProcessInfo) -> some View {
        HStack(spacing: 10) {
            appIcon(for: app)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 6) {
                    Text("PID \(app.pid)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let bundleId = app.bundleIdentifier {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text(bundleId)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()

            Button("Watch") {
                onSelect(app)
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func appIcon(for app: MonitoredProcessInfo) -> some View {
        if let runningApp = NSRunningApplication(processIdentifier: app.pid),
           let icon = runningApp.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "macwindow")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private func loadRunningApps() {
        runningApps = processService.runningApplications()
    }

    private func submitCustomPID() {
        guard let pid = parsedCustomPID else { return }
        customPIDError = nil

        if !processService.isProcessAlive(pid: pid) {
            customPIDError = "Process with PID \(pid) is not currently running."
            return
        }

        let name = customProcessName.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Process \(pid)"
            : customProcessName.trimmingCharacters(in: .whitespaces)

        let target = MonitoredProcessInfo(pid: pid, name: name, bundleIdentifier: nil, isRegularApp: false)
        onSelect(target)
        dismiss()
    }
}

// MARK: - ProcessPickerWindowController

/// Manages presenting the process picker in a dedicated floating window,
/// avoiding popover focus loss and premature dismissals on macOS.
@MainActor
public final class ProcessPickerWindowController: NSObject, NSWindowDelegate {
    public static let shared = ProcessPickerWindowController()

    private var window: NSWindow?
    private var onSelectCallback: ((MonitoredProcessInfo) -> Void)?

    public func present(onSelect: @escaping (MonitoredProcessInfo) -> Void) {
        self.onSelectCallback = onSelect

        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = ProcessPickerSheet(
            onSelect: { [weak self] target in
                self?.onSelectCallback?(target)
                self?.close()
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )

        let hostingController = NSHostingController(rootView: contentView)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Watch Application or Process"
        win.contentViewController = hostingController
        win.center()
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.delegate = self

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        window?.close()
        window = nil
        onSelectCallback = nil
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
        onSelectCallback = nil
    }
}
