import SwiftUI

struct ContentView: View {
    @StateObject private var model = WebViewModel()
    @StateObject private var settings = Settings.shared
    @State private var showSettings = false
    @State private var showError = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let home = settings.homeURL {
                WebView(model: model, initialURL: home)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            toolbar
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
        .onChange(of: model.errorMessage) { _, newValue in
            showError = newValue != nil
        }
        .alert("Can't load page", isPresented: $showError) {
            Button("Retry") {
                model.errorMessage = nil
                model.reload()
            }
            Button("Home") {
                model.errorMessage = nil
                model.goHome()
            }
            Button("Cancel", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            toolButton(systemName: "chevron.backward", enabled: model.canGoBack) {
                model.goBack()
            }
            toolButton(systemName: "chevron.forward", enabled: model.canGoForward) {
                model.goForward()
            }
            toolButton(systemName: "house.fill", enabled: true) {
                model.goHome()
            }
            toolButton(systemName: model.isLoading ? "xmark" : "arrow.clockwise", enabled: true) {
                if model.isLoading {
                    model.stop()
                } else {
                    model.reload()
                }
            }
            toolButton(systemName: "gearshape", enabled: true) {
                showSettings = true
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 10)
    }

    private func toolButton(systemName: String,
                            enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 42, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .disabled(!enabled)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Start page") {
                    TextField(Config.defaultHomeURL, text: $settings.homeURLString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Reset to default") {
                        settings.reset()
                    }
                }

                Section("Notes") {
                    Text("Use a hostname or IP this device can reach. On Tailscale, enable MagicDNS or use the 100.x address. The Home button loads this page.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
