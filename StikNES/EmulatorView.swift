//
//  EmulatorView.swift
//  StikNES
//
//  Created by Stephen on 12/30/24.
//

import SwiftUI
import WebKit
import GameController
import Combine

struct EmulatorView: View {
    let game: String
    @State private var virtualController: GCVirtualController?
    @StateObject private var webViewModel = WebViewModel()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isAutoSprintEnabled") private var isAutoSprintEnabled = false
    @AppStorage("isVirtualControllerVisible") private var isVirtualControllerVisible = true
    @State private var autoSprintCancellable: AnyCancellable?
    @State private var isCreditsPresented = false
    @State private var showQuitConfirmation = false

    var body: some View {
        NavigationView {
            VStack {
                NESWebView(game: game, webViewModel: webViewModel)
                    .onAppear {
                        setupPhysicalController()
                        if isVirtualControllerVisible {
                            setupVirtualController()
                        }
                    }
                    .onDisappear {
                        disconnectVirtualController()
                        stopListeningForPhysicalControllers()
                    }
            }
            .background(Color.black)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Toggle("Auto Sprint", isOn: $isAutoSprintEnabled)
                            .onChange(of: isAutoSprintEnabled) { enabled in
                                handleAutoSprintToggle(enabled: enabled)
                            }
                        Toggle("Show Virtual Controller", isOn: $isVirtualControllerVisible)
                            .onChange(of: isVirtualControllerVisible) { isVisible in
                                if isVisible {
                                    setupVirtualController()
                                } else {
                                    disconnectVirtualController()
                                }
                            }
                        Button(action: {
                            isCreditsPresented.toggle()
                        }) {
                            Label("Credits", systemImage: "info.circle")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showQuitConfirmation = true
                        } label: {
                            Label("Quit", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 24, weight: .bold)) // Increased size
                    }
                }
            }
            .sheet(isPresented: $isCreditsPresented) {
                CreditsView()
            }
            .confirmationDialog(
                "Are you sure you want to quit?",
                isPresented: $showQuitConfirmation,
                titleVisibility: .visible
            ) {
                Button("Quit", role: .destructive) {
                    quitGame()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .navigationBarBackButtonHidden(true)
    }

    private func setupVirtualController() {
        guard isVirtualControllerVisible else { return }
        guard webViewModel.isWebViewReady else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.setupVirtualController()
            }
            return
        }

        let virtualConfig = GCVirtualController.Configuration()
        virtualConfig.elements = [
            GCInputDirectionPad,
            GCInputButtonA,
            GCInputButtonB,
            GCInputLeftShoulder,
            GCInputRightShoulder
        ]

        virtualController = GCVirtualController(configuration: virtualConfig)
        virtualController?.connect()

        virtualController?.controller?.extendedGamepad?.valueChangedHandler = { gamepad, _ in
            guard let webView = self.webViewModel.webView else { return }
            self.handleGamepadInput(gamepad, webView: webView)
        }
    }

    private func setupPhysicalController() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { _ in
            self.configurePhysicalControllers()
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { _ in
            // Handle controller disconnection if necessary
        }

        configurePhysicalControllers() // For already connected controllers
    }

    private func configurePhysicalControllers() {
        for controller in GCController.controllers() {
            guard let gamepad = controller.extendedGamepad else { continue }
            gamepad.valueChangedHandler = { [self] gamepad, _ in
                guard let webView = webViewModel.webView else { return }
                handleGamepadInput(gamepad, webView: webView)
            }
        }
    }

    private func disconnectVirtualController() {
        virtualController?.disconnect()
        virtualController = nil
        autoSprintCancellable?.cancel()
    }

    private func stopListeningForPhysicalControllers() {
        NotificationCenter.default.removeObserver(self, name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.removeObserver(self, name: .GCControllerDidDisconnect, object: nil)
    }

    private func quitGame() {
        dismiss()
    }

    private func handleGamepadInput(_ gamepad: GCExtendedGamepad, webView: WKWebView) {
        handleDirectionPad(gamepad.dpad, webView: webView)
        mapButton(gamepad.buttonA, keyCode: 65, webView: webView) // A button
        mapButton(gamepad.rightShoulder, keyCode: 32, webView: webView) // Right Shoulder (e.g., Space)
        mapButton(gamepad.leftShoulder, keyCode: 83, webView: webView) // Left Shoulder (e.g., S)

        // Map the B button based on auto-sprint state
        let bKeyCode = isAutoSprintEnabled ? 0 : 66
        mapButton(gamepad.buttonB, keyCode: bKeyCode, webView: webView)
    }

    private func handleDirectionPad(_ dpad: GCControllerDirectionPad, webView: WKWebView) {
        mapButton(dpad.up, keyCode: 38, webView: webView)
        mapButton(dpad.down, keyCode: 40, webView: webView)

        if isAutoSprintEnabled {
            if dpad.left.isPressed || dpad.right.isPressed {
                sendKeyPress(keyCode: 66, webView: webView)
            } else {
                sendKeyUp(keyCode: 66, webView: webView)
            }
        }

        mapButton(dpad.left, keyCode: 37, webView: webView)
        mapButton(dpad.right, keyCode: 39, webView: webView)
    }

    private func mapButton(_ button: GCControllerButtonInput, keyCode: Int, webView: WKWebView) {
        if keyCode > 0 { // Ignore invalid key codes
            if button.isPressed {
                sendKeyPress(keyCode: keyCode, webView: webView)
            } else {
                sendKeyUp(keyCode: keyCode, webView: webView)
            }
        }
    }

    private func sendKeyPress(keyCode: Int, webView: WKWebView) {
        let jsCode = """
        (function() {
            var event = new KeyboardEvent('keydown', {
                keyCode: \(keyCode),
                which: \(keyCode),
                bubbles: true,
                cancelable: true
            });
            document.dispatchEvent(event);
        })();
        """
        webView.evaluateJavaScript(jsCode, completionHandler: nil)
    }

    private func sendKeyUp(keyCode: Int, webView: WKWebView) {
        let jsCode = """
        (function() {
            var event = new KeyboardEvent('keyup', {
                keyCode: \(keyCode),
                which: \(keyCode),
                bubbles: true,
                cancelable: true
            });
            document.dispatchEvent(event);
        })();
        """
        webView.evaluateJavaScript(jsCode, completionHandler: nil)
    }

    private func handleAutoSprintToggle(enabled: Bool) {
        guard let webView = webViewModel.webView else { return }
        if enabled {
            autoSprintCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    self.sendKeyPress(keyCode: 66, webView: webView)
                }
        } else {
            autoSprintCancellable?.cancel()
            sendKeyUp(keyCode: 66, webView: webView)
        }
    }
}

struct CreditsView: View {
    var body: some View {
        NavigationView {
            VStack {
                // Swipe down to dismiss message with arrows
                HStack {
                    Image(systemName: "arrow.down")
                        .foregroundColor(.secondary)
                    Text("Swipe down to dismiss")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "arrow.down")
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                // Main content
                Form {
                    Section(header: Text("Acknowledgements").font(.headline)) {
                        Text("This application was made possible with the support of open-source projects and contributions.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    }
                    Section(header: Text("Open Source Projects").font(.headline)) {
                        Link(destination: URL(string: "https://github.com/httpswift/swifter")!) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Swifter")
                                        .font(.body)
                                    Text("BSD-3-Clause License")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                        Link(destination: URL(string: "https://github.com/takahirox/nes-rust")!) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("NES Rust")
                                        .font(.body)
                                    Text("MIT License")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Section(header: Text("Community").font(.headline)) {
                        Link(destination: URL(string: "https://discord.gg/a6qxs97Gun")!) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Join our Discord")
                                        .font(.body)
                                    Text("Stay connected and join the discussion!")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct NESWebView: UIViewRepresentable {
    var game: String
    @ObservedObject var webViewModel: WebViewModel

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webViewModel.webView = webView
        webViewModel.isWebViewReady = true

        if let url = URL(string: "http://127.0.0.1:8080/index.html?rom=\(game)") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

class WebViewModel: ObservableObject {
    @Published var webView: WKWebView?
    @Published var isWebViewReady = false
}
