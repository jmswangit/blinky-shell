import SwiftUI

struct ContentView: View {
    @StateObject private var model = WebViewModel()
    @StateObject private var settings = Settings.shared
    @State private var showSettings = false
    @State private var showError = false
    @State private var toolbarExpanded = true
    @State private var collapseWorkItem: DispatchWorkItem?
    @State private var sessionImporter = SessionImporter()

    private let collapseDelay: TimeInterval = 5

    var body: some View {
        ZStack(alignment: .bottom) {
            if let home = settings.homeURL {
                WebView(model: model, initialURL: home)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            if toolbarExpanded {
                toolbar
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
            } else {
                collapsedButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottomLeading)))
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings, onImportSession: { sessionImporter.start() })
        }
        .onChange(of: model.errorMessage) { _, newValue in
            showError = newValue != nil
        }
        .onChange(of: showSettings) { _, isShowing in
            if isShowing {
                cancelCollapse()
            } else {
                scheduleCollapse()
            }
        }
        .onAppear {
            scheduleCollapse()
            sessionImporter.onCookies = { cookies in
                model.setCookies(cookies)
            }
            sessionImporter.onError = { message in
                model.errorMessage = message
            }
        }
        .onDisappear {
            cancelCollapse()
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

    private var collapsedButton: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                toolbarExpanded = true
            }
            scheduleCollapse()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .opacity(0.9)
    }

    private func toolButton(systemName: String,
                            enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button {
            action()
            scheduleCollapse()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 42, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .disabled(!enabled)
    }

    private func scheduleCollapse() {
        cancelCollapse()
        let work = DispatchWorkItem {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                toolbarExpanded = false
            }
            collapseWorkItem = nil
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
    }

    private func cancelCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    var onImportSession: () -> Void
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

                Section("Authentik session") {
                    Button("Refresh session from Safari") {
                        onImportSession()
                    }
                    Text("Opens auth.swan.cool in Safari. Log in with your passkey, and the session cookie is copied into the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
