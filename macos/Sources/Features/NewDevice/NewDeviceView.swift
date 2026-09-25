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
        .frame(width: 620, height: 700)
        .task { await model.load() }
    }

    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hardware").font(.headline)
                InfoButton(title: "What is Hardware?") {
                    Text("The phone or tablet the emulator pretends to be: its screen size, resolution and shape.")
                    Text("It doesn't change the Android version, and apps run the same on every choice. Pick one that matches the devices your users have, or a tablet or foldable to test those layouts.")
                    Text("You can change RAM, storage and resolution later with Edit.")
                        .foregroundStyle(.secondary)
                }
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
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
                InfoButton(title: "What is the Android version?") {
                    Text("The Android release the emulator runs. It's a separate download (a \"system image\", about 1–2 GB each) that you can reuse for any number of emulators.")
                    Text("Choose the newest for current features, or an older one to test apps on older phones.")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("**Google Play**: includes the Play Store. Best for most people.")
                        Text("**Google APIs**: Google services without the Play Store, and you can get root access.")
                        Text("**16 KB pages**: for testing apps with native code on newer devices.")
                    }
                }
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
                // Only a real change counts as the user's own name. The field can write back its
                // current (empty) value when the sheet appears, which would otherwise stop name
                // suggestions and leave Create disabled.
                set: { newValue in
                    guard newValue != model.name else { return }
                    model.name = newValue
                    model.nameEdited = true
                }
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
        VStack(spacing: 5) {
            Image(systemName: profile.symbolName)
                .font(.system(size: 18))
                .frame(height: 22)
            Text(profile.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(6)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.background.secondary), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
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
