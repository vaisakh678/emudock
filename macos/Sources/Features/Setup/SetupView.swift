import SwiftUI

struct SetupView: View {
    let status: AndroidSDK.Status
    @Environment(SDKStatusModel.self) private var sdk
    @State private var setup = SetupModel()

    private static let licenseURL = URL(string: "https://developer.android.com/studio/terms")!

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up Android emulators")
                    .font(.largeTitle.bold())
                Text("EmuDock installs everything needed to run emulators, about 3 GB of downloads. Anything already installed is reused.")
                    .foregroundStyle(.secondary)
                Text("SDK location: \((status.root ?? AndroidSDK.defaultRoot).path(percentEncoded: false))")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(spacing: 0) {
                ForEach(setup.steps) { step in
                    StepRow(step: step)
                    if step.id != setup.steps.last?.id { Divider() }
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 10))

            Spacer(minLength: 0)

            HStack {
                Toggle(isOn: $setup.licensesAccepted) {
                    HStack(spacing: 4) {
                        Text("I accept the")
                        Link("Android SDK License Agreement", destination: Self.licenseURL)
                    }
                }
                .disabled(setup.isRunning)

                Spacer()

                if setup.isRunning {
                    Button("Cancel", role: .cancel) { setup.cancel() }
                } else {
                    Button(setup.hasFailed ? "Try Again" : "Install") { setup.start(using: sdk) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!setup.licensesAccepted)
                }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct StepRow: View {
    let step: SetupModel.Step

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.id.title)
                    .font(.headline)
                switch step.state {
                case .pending:
                    EmptyView()
                case let .running(fraction, detail):
                    if let fraction {
                        ProgressView(value: fraction)
                    }
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                case let .done(detail), let .skipped(detail):
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                case let .failed(message):
                    Text(message).font(.caption.monospaced()).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    @ViewBuilder
    private var icon: some View {
        switch step.state {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped:
            Image(systemName: "checkmark.circle").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
