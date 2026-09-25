import SwiftUI

struct NewDeviceView: View {
    @State var model: NewDeviceModel
    let onCreated: @MainActor () async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Device")
                .font(.title2.bold())
                .padding([.horizontal, .top], 24)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hardwareSection
                    imageSection
                    nameSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .disabled(model.isWorking)

            Divider()
            footer
                .padding(16)
        }
        .frame(width: 620, height: 640)
        .task { await model.load() }
    }

    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hardware").font(.headline)
                Spacer()
                if !model.otherHardware.isEmpty {
                    Toggle("Show all devices", isOn: $model.showAllHardware)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                }
            }
            if model.popularHardware.isEmpty {
                ProgressView().controlSize(.small)
            } else {
                hardwareGrid(model.popularHardware)
                if model.showAllHardware {
                    Text("More devices")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    hardwareGrid(model.otherHardware)
                }
            }
        }
    }

    private func hardwareGrid(_ profiles: [HardwareProfile]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
            ForEach(profiles) { profile in
                HardwareCard(profile: profile, isSelected: model.hardware == profile)
                    .onTapGesture { model.hardware = profile }
            }
        }
    }

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Android version").font(.headline)
                Spacer()
                Toggle("Show all image types", isOn: $model.showAllImageTypes)
                    .toggleStyle(.checkbox)
                    .font(.callout)
            }
            VStack(spacing: 0) {
                ForEach(model.visibleImages) { image in
                    ImageRow(image: image, isSelected: model.image == image)
                        .contentShape(.rect)
                        .onTapGesture { model.image = image }
                    Divider()
                }
                if model.isLoadingDownloads {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking for more Android versions…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 8))
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name").font(.headline)
            TextField("Name", text: Binding(
                get: { model.name },
                set: { model.name = $0; model.nameEdited = true }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            switch model.phase {
            case .editing:
                if let image = model.image, !image.isInstalled {
                    Label("\(image.title) will be downloaded first (about 1–2 GB).", systemImage: "arrow.down.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case let .working(fraction, detail):
                VStack(alignment: .leading, spacing: 4) {
                    if let fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            case let .failed(message):
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            if model.isWorking {
                Button("Cancel", role: .cancel) { model.cancel() }
            } else {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if case .failed = model.phase {
                    Button("Try Again") { model.dismissError() }
                } else {
                    Button("Create") {
                        model.create {
                            await onCreated()
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCreate)
                }
            }
        }
        .controlSize(.large)
    }
}

private struct HardwareCard: View {
    let profile: HardwareProfile
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: profile.symbolName)
                .font(.system(size: 26))
                .frame(height: 32)
            Text(profile.name)
                .font(.callout)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .padding(8)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.background.secondary), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(.rect)
    }
}

private struct ImageRow: View {
    let image: SystemImage
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(image.title)
                Text(image.tagDisplay).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if image.isInstalled {
                Text("Installed").font(.caption).foregroundStyle(.green)
            } else {
                Label("Download", systemImage: "arrow.down.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }
}
