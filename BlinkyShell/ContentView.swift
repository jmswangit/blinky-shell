import SwiftUI

struct ContentView: View {
    @StateObject private var model = WebViewModel()
    @StateObject private var settings = Settings.shared
    @State private var showSettings = false
    @State private var showError = false
    @State private var toolbarExpanded = true
    @State private var collapseWorkItem: DispatchWorkItem?
    @State private var sessionImporter = SessionImporter()
    @AppStorage("collapsedButtonX") private var collapsedButtonX: Double = -1
    @AppStorage("collapsedButtonY") private var collapsedButtonY: Double = -1
    @State private var collapsedDragOffset: CGSize = .zero

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
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
            } else {
                GeometryReader { geo in
                    collapsedButton(in: geo.size)
                }
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

    private func collapsedButton(in size: CGSize) -> some View {
        let half: CGFloat = 23
        let maxX = max(size.width - half, half)
        let maxY = max(size.height - half, half)
        let defaultX = min(max(14 + half, half), maxX)
        let defaultY = min(max(size.height - 4 - half, half), maxY)
        let baseX = collapsedButtonX < 0 ? defaultX : CGFloat(collapsedButtonX) * size.width
        let baseY = collapsedButtonY < 0 ? defaultY : CGFloat(collapsedButtonY) * size.height
        let x = min(max(baseX + collapsedDragOffset.width, half), maxX)
        let y = min(max(baseY + collapsedDragOffset.height, half), maxY)

        return Image(systemName: "ellipsis")
            .font(.system(size: 18, weight: .bold))
            .frame(width: 46, height: 46)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(
                Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 6)
            .foregroundStyle(.primary)
            .opacity(0.9)
            .contentShape(Circle())
            .position(x: x, y: y)
            .onTapGesture {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    toolbarExpanded = true
                }
                scheduleCollapse()
            }
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.2)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { value in
                        if case .second(true, let drag?) = value {
                            collapsedDragOffset = drag.translation
                        }
                    }
                    .onEnded { value in
                        if case .second(true, let drag?) = value {
                            let newX = min(max(baseX + drag.translation.width, half), maxX)
                            let newY = min(max(baseY + drag.translation.height, half), maxY)
                            collapsedButtonX = Double(newX / size.width)
                            collapsedButtonY = Double(newY / size.height)
                        }
                        collapsedDragOffset = .zero
                    }
            )
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
