import SwiftUI

struct EditDeviceView: View {
    @State var model: EditDeviceModel
    @Environment(DevicesModel.self) private var devices
    @Environment(\.dismiss) private var dismiss

    private var isStopped: Bool { devices.state(of: model.avd) == .stopped }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit \(model.avd.displayName)")
                    .font(.title2.bold())
                Text(model.avd.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 8)

            Form {
                Section {
                    TextField("Name", text: $model.settings.name)
                } footer: {
                    Text("Emulator ID: \(model.avd.id) (used by the emulator command; doesn't change)")
                        .foregroundStyle(.secondary)
                }
                performanceSection
                storageSection
                displaySection
                inputSection
                bootSection
            }
            .formStyle(.grouped)
            .disabled(!isStopped)

            Divider()
            footer
                .padding(16)
        }
        .frame(width: 560, height: 680)
    }

    private var performanceSection: some View {
        Section {
            Picker("Memory (RAM)", selection: $model.settings.ramMB) {
                ForEach(model.ramOptions, id: \.self) { Text(AVDSettings.sizeTitle($0)).tag($0) }
            }
            Picker("CPU cores", selection: $model.settings.cpuCores) {
                ForEach(model.coreOptions, id: \.self) { Text("\($0)").tag($0) }
            }
            HStack {
                Spacer()
                Button("Use Recommended (\(AVDSettings.sizeTitle(HostResources.recommendedRAM)), \(HostResources.recommendedCores) cores)") {
                    model.applyRecommended()
                }
            }
        } header: {
            Text("Performance")
        } footer: {
            Text("This Mac has \(AVDSettings.sizeTitle(HostResources.memoryMB)) of memory and \(HostResources.cores) cores.")
                .foregroundStyle(.secondary)
        }
    }

    private var storageSection: some View {
        Section {
            Picker("Internal storage", selection: $model.settings.storageMB) {
                ForEach(model.storageOptions, id: \.self) { Text(AVDSettings.sizeTitle($0)).tag($0) }
            }
            if model.storageChanged {
                Toggle("Erase all apps and data to apply the new size", isOn: $model.eraseData)
            }
        } header: {
            Text("Storage")
        } footer: {
            if model.storageChanged {
                Text("The emulator starts fresh, like a factory reset. This can't be undone.")
                    .foregroundStyle(model.eraseData ? .red : .secondary)
            }
        }
    }

    private var displaySection: some View {
        Section {
            Toggle("Custom resolution", isOn: $model.customResolution)
            if model.customResolution {
                TextField("Width (px)", value: $model.settings.resolution.width, format: .number.grouping(.never))
                TextField("Height (px)", value: $model.settings.resolution.height, format: .number.grouping(.never))
                TextField("Density (dpi)", value: $model.settings.resolution.density, format: .number.grouping(.never))
            } else {
                Picker("Resolution", selection: $model.settings.resolution) {
                    ForEach(model.resolutionOptions, id: \.resolution) { option in
                        Text("\(option.name) · \(option.resolution.title)").tag(option.resolution)
                    }
                }
            }
            Picker("Orientation", selection: $model.settings.orientation) {
                Text("Portrait").tag(AVDSettings.Orientation.portrait)
                Text("Landscape").tag(AVDSettings.Orientation.landscape)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Display")
        } footer: {
            if !model.settings.resolution.isValid {
                Text("Width and height must be 240–4096 px, density 120–640 dpi.")
                    .foregroundStyle(.red)
            } else if model.switchesSkin {
                Text("The device frame changes to a plain frame sized for the new resolution.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inputSection: some View {
        Section("Input & cameras") {
            Toggle("Type with the Mac keyboard", isOn: $model.settings.hostKeyboard)
            Picker("Back camera", selection: $model.settings.backCamera) {
                ForEach(AVDSettings.Camera.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Front camera", selection: $model.settings.frontCamera) {
                ForEach(AVDSettings.Camera.allCases.filter { $0 != .virtualscene }, id: \.self) { Text($0.title).tag($0) }
            }
        }
    }

    private var bootSection: some View {
        Section {
            Toggle("Always cold boot", isOn: $model.settings.alwaysColdBoot)
            Toggle("Show device frame", isOn: $model.settings.deviceFrame)
        } header: {
            Text("Boot & window")
        } footer: {
            Text("Cold boot starts Android from scratch each time instead of resuming a saved snapshot. Slower, but avoids snapshot problems.")
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !isStopped {
                Label("Stop this emulator to edit it.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
            } else if model.hasChanges {
                Text("Changes apply the next time the emulator starts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                if model.save() {
                    Task {
                        await devices.refresh()
                        dismiss()
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canSave || !isStopped)
        }
        .controlSize(.large)
    }
}
