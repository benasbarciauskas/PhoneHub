import SwiftUI
import PhoneHubCore

/// Read-only notification list for the focused device (Android via dumpsys).
struct NotificationsPanel: View {
    let focused: Device?

    @State private var notifications: [PhoneNotification] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastRefresh: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            header
            content
        }
        .padding(.bottom, Theme.s3)
        .task(id: focused?.id) {
            await load(auto: true)
            // Light auto-refresh while this panel stays visible.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { break }
                await load(auto: true)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Notifications")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Spacer()
            if let lastRefresh, focused?.platform == .android {
                Text(lastRefresh, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.subtext)
            }
            if focused?.platform == .android {
                Button {
                    Task { await load(auto: false) }
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.subtext)
                .disabled(isLoading || focused == nil)
                .help("Refresh notifications")
            }
        }
        .padding(.horizontal, Theme.s3)
    }

    @ViewBuilder
    private var content: some View {
        if focused == nil {
            emptyCaption("Select a device to view notifications.")
        } else if focused?.platform == .ios {
            emptyCaption("Notifications aren't available for iOS devices (no API).")
        } else if let errorMessage, notifications.isEmpty {
            emptyCaption(errorMessage)
        } else if notifications.isEmpty && !isLoading {
            emptyCaption("No active notifications.")
        } else {
            LazyVStack(spacing: Theme.s1) {
                ForEach(notifications) { note in
                    NotificationRow(note: note)
                }
            }
            .padding(.horizontal, Theme.s2)
        }
    }

    private func emptyCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.subtext)
            .padding(.horizontal, Theme.s3)
            .padding(.top, Theme.s2)
    }

    @MainActor
    private func load(auto: Bool) async {
        guard let device = focused, device.platform == .android else {
            notifications = []
            errorMessage = nil
            return
        }
        // Avoid stacking spinners on quiet auto-refresh when we already have rows.
        if !auto || notifications.isEmpty {
            isLoading = true
        }
        defer { isLoading = false }

        let serial = device.id
        let result = await Task.detached(priority: .userInitiated) {
            NotificationReader.fetch(serial: serial)
        }.value

        notifications = result
        lastRefresh = Date()
        // Empty is valid (none posted); adb failure also returns []. Soft hint on manual refresh only.
        if !auto, result.isEmpty {
            errorMessage = "No active notifications (or adb could not read dumpsys)."
        } else {
            errorMessage = nil
        }
    }
}

private struct NotificationRow: View {
    let note: PhoneNotification

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(shortPackage(note.package))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
            if !note.title.isEmpty {
                Text(note.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
            }
            if !note.text.isEmpty {
                Text(note.text)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.subtext)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.s2)
        .cardSurface(elevated: true)
    }

    /// Last path component of package for a compact label.
    private func shortPackage(_ pkg: String) -> String {
        pkg.split(separator: ".").last.map(String.init) ?? pkg
    }
}
