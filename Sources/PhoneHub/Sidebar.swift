import SwiftUI
import PhoneHubCore

struct Sidebar: View {
    @Bindable var store: DeviceStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack {
                Text("Devices").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Picker("Layout", selection: $store.layout) {
                    ForEach(StageLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 112)
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(Theme.subtext)
            }
            .padding(.horizontal, Theme.s3).padding(.top, Theme.s3)

            if store.toolMissing {
                Text("adb not found — `brew install android-platform-tools`")
                    .font(.caption).foregroundStyle(Theme.warn)
                    .padding(.horizontal, Theme.s3)
            }

            ScrollView {
                VStack(spacing: Theme.s1) {
                    ForEach(store.devices) { device in
                        DeviceRow(device: device, selected: device.id == store.focusedDevice?.id)
                            .onTapGesture { withAnimation(Theme.selection) { store.setFocused(device) } }
                    }
                    if store.devices.isEmpty && !store.toolMissing {
                        Text("No devices connected").font(.caption)
                            .foregroundStyle(Theme.subtext).padding(.top, Theme.s4)
                    }
                }
                .padding(.horizontal, Theme.s2)
            }
        }
        .frame(width: 240)
        .background(Theme.surface)
    }
}

private struct DeviceRow: View {
    let device: Device
    let selected: Bool

    var statusColor: Color {
        if device.platform == .ios {
            return device.status == "connected" ? Theme.ok : Theme.warn
        }

        switch device.status {
        case "device": return Theme.ok
        case "unauthorized": return Theme.warn
        default: return Theme.err
        }
    }

    var body: some View {
        HStack(spacing: Theme.s2) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.model).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Text(device.platform == .android ? "Android \(device.osVersion)" : "iOS \(device.osVersion)")
                    .font(.system(size: 11)).foregroundStyle(Theme.subtext)
            }
            Spacer()
        }
        .padding(.vertical, Theme.s2).padding(.horizontal, Theme.s3)
        .background(selected ? Theme.elevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
    }
}
