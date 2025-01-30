//
//  EmulatorView.swift
//  StikNES
//
//  Created by Stephen on 12/30/24.
//

import SwiftUI
import Combine
import WebKit
import GameController
import UniformTypeIdentifiers
import PhotosUI
import UIKit

struct EmulatorView: View {
    let game: String
    @StateObject private var webViewModel = WebViewModel()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isAutoSprintEnabled") private var isAutoSprintEnabled = false
    @AppStorage("isHapticFeedbackEnabled") private var isHapticFeedbackEnabled = false
    @State private var didInitialize = false
    @State private var autoSprintCancellable: AnyCancellable?
    @State private var isCreditsPresented = false
    @State private var showQuitConfirmation = false
    @State private var isEditingLayout = false
    @State private var showingPhotoPickerLandscape = false
    @State private var showingPhotoPickerPortrait = false
    @State private var selectedPhotoLandscape: PhotosPickerItem?
    @State private var selectedPhotoPortrait: PhotosPickerItem?
    @State private var customButtonsPortrait: [CustomButton] = [
        CustomButton(label: "Up", keyCode: 38,
                    x: UIScreen.main.bounds.width * 0.22,
                    y: UIScreen.main.bounds.height * 0.12,
                    width: 60, height: 60),
        CustomButton(label: "Down", keyCode: 40,
                    x: UIScreen.main.bounds.width * 0.22,
                    y: UIScreen.main.bounds.height * 0.25,
                    width: 60, height: 60),
        CustomButton(label: "Left", keyCode: 37,
                    x: UIScreen.main.bounds.width * 0.05,
                    y: UIScreen.main.bounds.height * 0.185,
                    width: 60, height: 60),
        CustomButton(label: "Right", keyCode: 39,
                    x: UIScreen.main.bounds.width * 0.39,
                    y: UIScreen.main.bounds.height * 0.185,
                    width: 60, height: 60),
        
        CustomButton(label: "A", keyCode: 65,
                    x: UIScreen.main.bounds.width * 0.85,
                    y: UIScreen.main.bounds.height * 0.15,
                    width: 60, height: 60),
        CustomButton(label: "B", keyCode: 66,
                    x: UIScreen.main.bounds.width * 0.65,
                    y: UIScreen.main.bounds.height * 0.24,
                    width: 60, height: 60),
        
        CustomButton(label: "Start", keyCode: 32,
                    x: UIScreen.main.bounds.width * 0.60,
                    y: UIScreen.main.bounds.height * 0.32,
                    width: 60, height: 60),
        CustomButton(label: "Select", keyCode: 83,
                    x: UIScreen.main.bounds.width * 0.40,
                    y: UIScreen.main.bounds.height * 0.32,
                    width: 60, height: 60),
        CustomButton(label: "Reset", keyCode: 82,
                    x: UIScreen.main.bounds.width * 0.05,
                    y: UIScreen.main.bounds.height * 0.32,
                    width: 60, height: 60)
    ]
    @State private var customButtonsLandscape: [CustomButton] = [
        CustomButton(label: "Up", keyCode: 38, x: 100, y: 40, width: 60, height: 60),
        CustomButton(label: "Down", keyCode: 40, x: 100, y: 160, width: 60, height: 60),
        CustomButton(label: "Left", keyCode: 37, x: 40, y: 100, width: 60, height: 60),
        CustomButton(label: "Right", keyCode: 39, x: 160, y: 100, width: 60, height: 60),
        CustomButton(label: "A", keyCode: 65, x: 600, y: 80, width: 60, height: 60),
        CustomButton(label: "B", keyCode: 66, x: 540, y: 100, width: 60, height: 60),
        CustomButton(label: "Start", keyCode: 32, x: 300, y: 70, width: 60, height: 60),
        CustomButton(label: "Select", keyCode: 83, x: 360, y: 70, width: 60, height: 60),
        CustomButton(label: "Reset", keyCode: 82, x: 300, y: 120, width: 60, height: 60)
    ]
    @State private var importedPNGDataLandscape: Data? = nil
    @State private var importedPNGDataPortrait: Data? = nil
    @State private var activePresses = Set<Int>()
    var body: some View {
        let nesWebView = NESWebView(game: game, webViewModel: webViewModel)
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                GeometryReader { geometry in
                    let isPortrait = geometry.size.height > geometry.size.width
                    let displayedButtons = isPortrait ? $customButtonsPortrait : $customButtonsLandscape
                    let pngDataToUse = isPortrait ? importedPNGDataPortrait : importedPNGDataLandscape
                    if isPortrait {
                        VStack(spacing: 0) {
                            nesWebView
                                .frame(width: geometry.size.width, height: geometry.size.height * 0.5)
                            PNGOverlay(
                                pressHandler: { keyCode in onScreenPress(keyCode: keyCode) },
                                releaseHandler: { keyCode in onScreenRelease(keyCode: keyCode) },
                                isEditing: isEditingLayout,
                                buttons: displayedButtons,
                                importedPNGData: pngDataToUse,
                                isPortrait: true
                            )
                            .frame(width: geometry.size.width, height: geometry.size.height * 0.5)
                        }
                    } else {
                        ZStack {
                            nesWebView
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            PNGOverlay(
                                pressHandler: { keyCode in onScreenPress(keyCode: keyCode) },
                                releaseHandler: { keyCode in onScreenRelease(keyCode: keyCode) },
                                isEditing: isEditingLayout,
                                buttons: displayedButtons,
                                importedPNGData: pngDataToUse,
                                isPortrait: false
                            )
                            .edgesIgnoringSafeArea(.all)
                        }
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
            .onAppear {
                if !didInitialize {
                    didInitialize = true
                    setupPhysicalController()
                    loadAllButtonLayouts()
                    importedPNGDataLandscape = loadPNG(key: "importedPNGLandscape")
                    importedPNGDataPortrait = loadPNG(key: "importedPNGPortrait")
                }
            }
            .onDisappear {
                stopListeningForPhysicalControllers()
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Menu("Settings") {
                            Toggle(isOn: $isAutoSprintEnabled) { Label("Auto Sprint", systemImage: "hare.fill") }
                                .onChange(of: isAutoSprintEnabled) { enabled in handleAutoSprintToggle(enabled: enabled) }
                            Toggle(isOn: $isHapticFeedbackEnabled) { Label("Haptic Feedback", systemImage: "waveform.path.ecg") }
                        }
                        Menu("Layout") {
                            Button {
                                isEditingLayout.toggle()
                                if !isEditingLayout { saveCurrentOrientationLayout() }
                            } label: { Label("Customize Layout", systemImage: "rectangle.and.pencil.and.ellipsis") }
                            Button {
                                resetToDefaultLayoutCurrent()
                                saveCurrentOrientationLayout()
                            } label: { Label("Reset Layout (Current)", systemImage: "arrow.clockwise") }
                        }
                        Menu("Skins") {
                            Button {
                                showingPhotoPickerLandscape = true
                            } label: { Label("Import Skin (Landscape)", systemImage: "iphone.gen3.landscape") }
                            Button {
                                showingPhotoPickerPortrait = true
                            } label: { Label("Import Skin (Portrait)", systemImage: "iphone.gen3") }
                            Button {
                                resetSkinsToDefaults()
                            } label: { Label("Reset Skins to Defaults", systemImage: "arrow.clockwise") }
                        }
                        Menu("Other") {
                            Button {
                                isCreditsPresented.toggle()
                            } label: { Label("Credits", systemImage: "info.circle") }
                        }
                        Section {
                            Button(role: .destructive) {
                                showQuitConfirmation = true
                            } label: { Label("Quit", systemImage: "xmark.circle") }
                        }
                    } label: {
                        Label("Menu", systemImage: "ellipsis.circle.fill")
                            .font(.system(size: 22, weight: .bold))
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
            .photosPicker(
                isPresented: $showingPhotoPickerLandscape,
                selection: $selectedPhotoLandscape,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: selectedPhotoLandscape) { newItem in
                Task { await loadImageData(from: newItem, isLandscape: true) }
            }
            .photosPicker(
                isPresented: $showingPhotoPickerPortrait,
                selection: $selectedPhotoPortrait,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: selectedPhotoPortrait) { newItem in
                Task { await loadImageData(from: newItem, isLandscape: false) }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .navigationBarBackButtonHidden(true)
    }
    private func onScreenPress(keyCode: Int) {
        if !activePresses.contains(keyCode) {
            activePresses.insert(keyCode)
            sendKeyPress(keyCode: keyCode, webView: webViewModel.webView, shouldProvideHaptic: true)
        }
    }
    private func onScreenRelease(keyCode: Int) {
        if activePresses.contains(keyCode) {
            activePresses.remove(keyCode)
            sendKeyUp(keyCode: keyCode, webView: webViewModel.webView, shouldProvideHaptic: true)
        }
    }
    private func loadImageData(from item: PhotosPickerItem?, isLandscape: Bool) async {
        guard let item = item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                if isLandscape {
                    savePNG(data: data, key: "importedPNGLandscape")
                    importedPNGDataLandscape = data
                } else {
                    savePNG(data: data, key: "importedPNGPortrait")
                    importedPNGDataPortrait = data
                }
            }
        } catch {}
    }
    private func saveAllButtonLayouts() {
        saveButtonArray(customButtonsPortrait, key: "buttonLayoutPortrait")
        saveButtonArray(customButtonsLandscape, key: "buttonLayoutLandscape")
    }
    private func loadAllButtonLayouts() {
        if let loaded = loadButtonArray(key: "buttonLayoutPortrait") {
            customButtonsPortrait = loaded
        }
        if let loaded = loadButtonArray(key: "buttonLayoutLandscape") {
            customButtonsLandscape = loaded
        }
    }
    private func saveCurrentOrientationLayout() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        let size = window.bounds.size
        let isPortrait = size.height > size.width
        if isPortrait {
            saveButtonArray(customButtonsPortrait, key: "buttonLayoutPortrait")
        } else {
            saveButtonArray(customButtonsLandscape, key: "buttonLayoutLandscape")
        }
    }
    private func resetToDefaultLayoutCurrent() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        let size = window.bounds.size
        let isPortrait = size.height > size.width
        if isPortrait {
            customButtonsPortrait = [
                CustomButton(label: "Up", keyCode: 38,
                            x: UIScreen.main.bounds.width * 0.22,
                            y: UIScreen.main.bounds.height * 0.12,
                            width: 60, height: 60),
                CustomButton(label: "Down", keyCode: 40,
                            x: UIScreen.main.bounds.width * 0.22,
                            y: UIScreen.main.bounds.height * 0.25,
                            width: 60, height: 60),
                CustomButton(label: "Left", keyCode: 37,
                            x: UIScreen.main.bounds.width * 0.05,
                            y: UIScreen.main.bounds.height * 0.185,
                            width: 60, height: 60),
                CustomButton(label: "Right", keyCode: 39,
                            x: UIScreen.main.bounds.width * 0.39,
                            y: UIScreen.main.bounds.height * 0.185,
                            width: 60, height: 60),
                
                CustomButton(label: "A", keyCode: 65,
                            x: UIScreen.main.bounds.width * 0.85,
                            y: UIScreen.main.bounds.height * 0.15,
                            width: 60, height: 60),
                CustomButton(label: "B", keyCode: 66,
                            x: UIScreen.main.bounds.width * 0.65,
                            y: UIScreen.main.bounds.height * 0.24,
                            width: 60, height: 60),
                
                CustomButton(label: "Start", keyCode: 32,
                            x: UIScreen.main.bounds.width * 0.60,
                            y: UIScreen.main.bounds.height * 0.32,
                            width: 60, height: 60),
                CustomButton(label: "Select", keyCode: 83,
                            x: UIScreen.main.bounds.width * 0.40,
                            y: UIScreen.main.bounds.height * 0.32,
                            width: 60, height: 60),
                CustomButton(label: "Reset", keyCode: 82,
                            x: UIScreen.main.bounds.width * 0.05,
                            y: UIScreen.main.bounds.height * 0.32,
                            width: 60, height: 60)
            ]
        } else {
            customButtonsLandscape = [
                CustomButton(label: "Up", keyCode: 38, x: 100, y: 40, width: 60, height: 60),
                CustomButton(label: "Down", keyCode: 40, x: 100, y: 160, width: 60, height: 60),
                CustomButton(label: "Left", keyCode: 37, x: 40, y: 100, width: 60, height: 60),
                CustomButton(label: "Right", keyCode: 39, x: 160, y: 100, width: 60, height: 60),
                CustomButton(label: "A", keyCode: 65, x: 600, y: 80, width: 60, height: 60),
                CustomButton(label: "B", keyCode: 66, x: 540, y: 100, width: 60, height: 60),
                CustomButton(label: "Start", keyCode: 32, x: 300, y: 70, width: 60, height: 60),
                CustomButton(label: "Select", keyCode: 83, x: 360, y: 70, width: 60, height: 60),
                CustomButton(label: "Reset", keyCode: 82, x: 300, y: 120, width: 60, height: 60)
            ]
        }
    }
    private func saveButtonArray(_ array: [CustomButton], key: String) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(array) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    private func loadButtonArray(key: String) -> [CustomButton]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode([CustomButton].self, from: data)
    }
    private func savePNG(data: Data, key: String) {
        UserDefaults.standard.set(data, forKey: key)
    }
    private func loadPNG(key: String) -> Data? {
        UserDefaults.standard.data(forKey: key)
    }
    private func resetSkinsToDefaults() {
        UserDefaults.standard.removeObject(forKey: "importedPNGLandscape")
        UserDefaults.standard.removeObject(forKey: "importedPNGPortrait")
        importedPNGDataLandscape = nil
        importedPNGDataPortrait = nil
    }
    private func setupPhysicalController() {
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { _ in
            configurePhysicalControllers()
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { _ in }
        configurePhysicalControllers()
    }
    private func stopListeningForPhysicalControllers() {
        NotificationCenter.default.removeObserver(self, name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.removeObserver(self, name: .GCControllerDidDisconnect, object: nil)
    }
    private func configurePhysicalControllers() {
        for controller in GCController.controllers() {
            guard let gamepad = controller.extendedGamepad else { continue }
            gamepad.valueChangedHandler = { gamepad, _ in
                guard let webView = webViewModel.webView else { return }
                handleGamepadInput(gamepad, webView: webView)
            }
        }
    }
    private func handleGamepadInput(_ gamepad: GCExtendedGamepad, webView: WKWebView) {
        handleDirectionPad(gamepad.dpad, webView: webView)
        let aKey = 65
        if gamepad.buttonA.isPressed {
            if !activePresses.contains(aKey) {
                activePresses.insert(aKey)
                sendKeyPress(keyCode: aKey, webView: webView, shouldProvideHaptic: true)
            }
        } else {
            if activePresses.contains(aKey) {
                activePresses.remove(aKey)
                sendKeyUp(keyCode: aKey, webView: webView, shouldProvideHaptic: true)
            }
        }
        let bKeyCode = isAutoSprintEnabled ? 0 : 66
        if bKeyCode > 0 {
            if gamepad.buttonB.isPressed {
                if !activePresses.contains(bKeyCode) {
                    activePresses.insert(bKeyCode)
                    sendKeyPress(keyCode: bKeyCode, webView: webView, shouldProvideHaptic: true)
                }
            } else {
                if activePresses.contains(bKeyCode) {
                    activePresses.remove(bKeyCode)
                    sendKeyUp(keyCode: bKeyCode, webView: webView, shouldProvideHaptic: true)
                }
            }
        }
    }
    private func handleDirectionPad(_ dpad: GCControllerDirectionPad, webView: WKWebView) {
        checkDpad(dpad.up, 38, webView)
        checkDpad(dpad.down, 40, webView)
        checkDpad(dpad.left, 37, webView)
        checkDpad(dpad.right, 39, webView)
        if isAutoSprintEnabled {
            if dpad.left.isPressed || dpad.right.isPressed {
                if !activePresses.contains(66) {
                    activePresses.insert(66)
                    sendKeyPress(keyCode: 66, webView: webView, shouldProvideHaptic: false)
                }
            } else {
                if activePresses.contains(66) {
                    activePresses.remove(66)
                    sendKeyUp(keyCode: 66, webView: webView, shouldProvideHaptic: false)
                }
            }
        }
    }
    private func checkDpad(_ pad: GCControllerButtonInput, _ code: Int, _ webView: WKWebView) {
        if pad.isPressed {
            if !activePresses.contains(code) {
                activePresses.insert(code)
                sendKeyPress(keyCode: code, webView: webView, shouldProvideHaptic: true)
            }
        } else {
            if activePresses.contains(code) {
                activePresses.remove(code)
                sendKeyUp(keyCode: code, webView: webView, shouldProvideHaptic: true)
            }
        }
    }
    private func eventProperties(for keyCode: Int) -> (String, String) {
        switch keyCode {
        case 37: return ("ArrowLeft", "ArrowLeft")
        case 38: return ("ArrowUp", "ArrowUp")
        case 39: return ("ArrowRight", "ArrowRight")
        case 40: return ("ArrowDown", "ArrowDown")
        case 32: return ("Space", " ")
        case 65: return ("KeyA", "a")
        case 66: return ("KeyB", "b")
        case 82: return ("KeyR", "r")
        case 83: return ("KeyS", "s")
        default: return ("", "")
        }
    }
    private func sendKeyPress(keyCode: Int, webView: WKWebView?, shouldProvideHaptic: Bool) {
        guard let webView = webView else { return }
        if shouldProvideHaptic && isHapticFeedbackEnabled {
            let f = UIImpactFeedbackGenerator(style: .rigid)
            f.prepare()
            f.impactOccurred()
        }
        let (c, k) = eventProperties(for: keyCode)
        let js = """
        (function() {
            var e = new KeyboardEvent('keydown', {
                bubbles: true,
                cancelable: true,
                code: '\(c)',
                key: '\(k)',
                keyCode: \(keyCode),
                which: \(keyCode)
            });
            document.dispatchEvent(e);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    private func sendKeyUp(keyCode: Int, webView: WKWebView?, shouldProvideHaptic: Bool) {
        guard let webView = webView else { return }
        if shouldProvideHaptic && isHapticFeedbackEnabled {
            let f = UIImpactFeedbackGenerator(style: .rigid)
            f.prepare()
            f.impactOccurred()
        }
        let (c, k) = eventProperties(for: keyCode)
        let js = """
        (function() {
            var e = new KeyboardEvent('keyup', {
                bubbles: true,
                cancelable: true,
                code: '\(c)',
                key: '\(k)',
                keyCode: \(keyCode),
                which: \(keyCode)
            });
            document.dispatchEvent(e);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    private func handleAutoSprintToggle(enabled: Bool) {
        guard let w = webViewModel.webView else { return }
        if enabled {
            autoSprintCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    if !activePresses.contains(66) {
                        activePresses.insert(66)
                        sendKeyPress(keyCode: 66, webView: w, shouldProvideHaptic: false)
                    }
                }
        } else {
            autoSprintCancellable?.cancel()
            if activePresses.contains(66) {
                activePresses.remove(66)
                sendKeyUp(keyCode: 66, webView: w, shouldProvideHaptic: false)
            }
        }
    }
    private func quitGame() {
        dismiss()
    }
}

struct CreditsView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            VStack {
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
                                    Text("Swifter").font(.body)
                                    Text("BSD-3-Clause License").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                        Link(destination: URL(string: "https://github.com/takahirox/nes-rust")!) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("NES Rust").font(.body)
                                    Text("MIT License").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Section(header: Text("Community").font(.headline)) {
                        Link(destination: URL(string: "https://discord.gg/a6qxs97Gun")!) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Join our Discord").font(.body)
                                    Text("Stay connected and join the discussion!").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                Button(action: { dismiss() }) {
                    Text("Close").font(.body).foregroundColor(.blue).padding()
                }
            }
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct NESWebView: UIViewRepresentable {
    let game: String
    @ObservedObject var webViewModel: WebViewModel
    func makeUIView(context: Context) -> WKWebView {
        if webViewModel.webView == nil {
            let w = WKWebView()
            webViewModel.webView = w
            if let url = URL(string: "http://127.0.0.1:8080/index.html?rom=\(game)") {
                w.load(URLRequest(url: url))
            }
        }
        return webViewModel.webView!
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

class WebViewModel: ObservableObject {
    @Published var webView: WKWebView?
}

struct CustomButton: Identifiable, Codable {
    let id: UUID
    let label: String
    let keyCode: Int
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    init(id: UUID = UUID(), label: String, keyCode: Int, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.id = id
        self.label = label
        self.keyCode = keyCode
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

struct DraggableButtonAreaView: View {
    @Binding var button: CustomButton
    let isEditing: Bool
    let screenSize: CGSize
    let pressHandler: (Int) -> Void
    let releaseHandler: (Int) -> Void
    @State private var dragOffset = CGSize.zero
    @State private var currentWidth: CGFloat = 0
    @State private var currentHeight: CGFloat = 0
    private let minButtonSize: CGFloat = 30
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .frame(width: button.width, height: button.height)
                .contentShape(Rectangle())
            if isEditing {
                Rectangle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: button.width, height: button.height)
                    .overlay(
                        Text(button.label)
                            .foregroundColor(.white)
                            .font(.footnote)
                            .padding(2)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4),
                        alignment: .center
                    )
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .padding(2)
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                let dw = v.translation.width
                                let dh = v.translation.height
                                let nw = max(minButtonSize, currentWidth + dw)
                                let nh = max(minButtonSize, currentHeight + dh)
                                if button.x + nw <= screenSize.width {
                                    button.width = nw
                                }
                                if button.y + nh <= screenSize.height {
                                    button.height = nh
                                }
                            }
                            .onEnded { _ in
                                currentWidth = button.width
                                currentHeight = button.height
                            }
                    )
            }
        }
        .position(
            x: min(max(button.x + dragOffset.width, button.width / 2), screenSize.width - button.width / 2),
            y: min(max(button.y + dragOffset.height, button.height / 2), screenSize.height - button.height / 2)
        )
        .gesture(
            isEditing
            ? DragGesture()
                .onChanged { v in dragOffset = v.translation }
                .onEnded { v in
                    button.x = min(max(button.x + v.translation.width, button.width / 2), screenSize.width - button.width / 2)
                    button.y = min(max(button.y + v.translation.height, button.height / 2), screenSize.height - button.height / 2)
                    dragOffset = .zero
                }
            : DragGesture(minimumDistance: 0)
                .onChanged { _ in pressHandler(button.keyCode) }
                .onEnded { _ in releaseHandler(button.keyCode) }
        )
        .onAppear {
            currentWidth = button.width
            currentHeight = button.height
        }
    }
}

struct PNGOverlay: View {
    let pressHandler: (Int) -> Void
    let releaseHandler: (Int) -> Void
    let isEditing: Bool
    @Binding var buttons: [CustomButton]
    let importedPNGData: Data?
    let isPortrait: Bool
    var body: some View {
        GeometryReader { g in
            let s = g.size
            ZStack {
                if let d = importedPNGData, let img = UIImage(data: d) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: s.width, height: s.height)
                } else {
                    if isPortrait {
                        if let defaultVertical = UIImage(named: "StikNES_Vertical") {
                            Image(uiImage: defaultVertical)
                                .resizable()
                                .scaledToFit()
                                .frame(width: s.width, height: s.height)
                        } else {
                            Rectangle().fill(Color.gray.opacity(0.5))
                            Text("No Skin Imported").foregroundColor(.white)
                        }
                    } else {
                        if let defaultHorizontal = UIImage(named: "StikNES_Horizontal") {
                            Image(uiImage: defaultHorizontal)
                                .resizable()
                                .scaledToFit()
                                .frame(width: s.width, height: s.height)
                        } else {
                            Rectangle().fill(Color.gray.opacity(0.5))
                            Text("No Skin Imported").foregroundColor(.white)
                        }
                    }
                }
                ForEach($buttons) { $btn in
                    DraggableButtonAreaView(
                        button: $btn,
                        isEditing: isEditing,
                        screenSize: s,
                        pressHandler: pressHandler,
                        releaseHandler: releaseHandler
                    )
                }
            }
        }
    }
}
