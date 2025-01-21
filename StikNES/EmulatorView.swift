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
import UIKit

// MARK: - EmulatorView
struct EmulatorView: View {
    let game: String
    
    @StateObject private var webViewModel = WebViewModel()
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("isAutoSprintEnabled") private var isAutoSprintEnabled = false
    
    // This flag ensures we only do setup once
    @State private var didInitialize = false
    
    @State private var autoSprintCancellable: AnyCancellable?
    @State private var isCreditsPresented = false
    @State private var showQuitConfirmation = false
    @State private var isEditingLayout = false
    
    // Two separate arrays: one for portrait, one for landscape
    @State private var customButtonsPortrait: [CustomButton] = [
        // Example defaults for portrait
        CustomButton(label: "Up",     keyCode: 38, x:  80, y:  80, width: 60, height: 60),
        CustomButton(label: "Down",   keyCode: 40, x:  80, y: 200, width: 60, height: 60),
        CustomButton(label: "Left",   keyCode: 37, x:  20, y: 140, width: 60, height: 60),
        CustomButton(label: "Right",  keyCode: 39, x: 140, y: 140, width: 60, height: 60),
        CustomButton(label: "A",      keyCode: 65, x: 240, y: 140, width: 60, height: 60),
        CustomButton(label: "B",      keyCode: 66, x: 300, y: 140, width: 60, height: 60),
        CustomButton(label: "Start",  keyCode: 32, x: 200, y: 250, width: 60, height: 60),
        CustomButton(label: "Select", keyCode: 83, x: 280, y: 250, width: 60, height: 60),
        CustomButton(label: "Reset",  keyCode: 82, x: 360, y: 250, width: 60, height: 60)
    ]
    
    @State private var customButtonsLandscape: [CustomButton] = [
        // Example defaults for landscape
        CustomButton(label: "Up",     keyCode: 38, x: 100, y:  40, width: 60, height: 60),
        CustomButton(label: "Down",   keyCode: 40, x: 100, y: 160, width: 60, height: 60),
        CustomButton(label: "Left",   keyCode: 37, x:  40, y: 100, width: 60, height: 60),
        CustomButton(label: "Right",  keyCode: 39, x: 160, y: 100, width: 60, height: 60),
        CustomButton(label: "A",      keyCode: 65, x: 600, y:  80, width: 60, height: 60),
        CustomButton(label: "B",      keyCode: 66, x: 540, y: 100, width: 60, height: 60),
        CustomButton(label: "Start",  keyCode: 32, x: 300, y:  70, width: 60, height: 60),
        CustomButton(label: "Select", keyCode: 83, x: 360, y:  70, width: 60, height: 60),
        CustomButton(label: "Reset",  keyCode: 82, x: 300, y: 120, width: 60, height: 60)
    ]
    
    // For PNG import
    @State private var showingFileImporterLandscape = false
    @State private var showingFileImporterPortrait  = false
    
    @State private var importedPNGDataLandscape: Data? = nil
    @State private var importedPNGDataPortrait:  Data? = nil
    
    var body: some View {
        // Create ONE NESWebView so it doesn't re-init on rotation
        let nesWebView = NESWebView(game: game, webViewModel: webViewModel)
        
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                GeometryReader { geometry in
                    let isPortrait = geometry.size.height > geometry.size.width
                    
                    // Decide which buttons array to show
                    let displayedButtons = isPortrait ? $customButtonsPortrait : $customButtonsLandscape
                    // Decide which PNG data to show
                    let pngDataToUse = isPortrait ? importedPNGDataPortrait : importedPNGDataLandscape
                    
                    if isPortrait {
                        // -- PORTRAIT LAYOUT --
                        VStack(spacing: 0) {
                            // Reuse the SAME web view up top
                            nesWebView
                                .frame(width: geometry.size.width,
                                       height: geometry.size.height * 0.5)
                            
                            PNGOverlay(
                                pressHandler: { keyCode in
                                    guard keyCode > 0 else { return }
                                    sendKeyPress(keyCode: keyCode, webView: webViewModel.webView)
                                },
                                releaseHandler: { keyCode in
                                    guard keyCode > 0 else { return }
                                    sendKeyUp(keyCode: keyCode, webView: webViewModel.webView)
                                },
                                isEditing: isEditingLayout,
                                buttons: displayedButtons,
                                importedPNGData: pngDataToUse
                            )
                            .frame(width: geometry.size.width,
                                   height: geometry.size.height * 0.5)
                        }
                    } else {
                        // -- LANDSCAPE LAYOUT --
                        ZStack {
                            // Reuse the SAME web view full-screen
                            nesWebView
                                .frame(width: geometry.size.width,
                                       height: geometry.size.height)
                            
                            PNGOverlay(
                                pressHandler: { keyCode in
                                    guard keyCode > 0 else { return }
                                    sendKeyPress(keyCode: keyCode, webView: webViewModel.webView)
                                },
                                releaseHandler: { keyCode in
                                    guard keyCode > 0 else { return }
                                    sendKeyUp(keyCode: keyCode, webView: webViewModel.webView)
                                },
                                isEditing: isEditingLayout,
                                buttons: displayedButtons,
                                importedPNGData: pngDataToUse
                            )
                            .edgesIgnoringSafeArea(.all)
                        }
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
            // Setup only once
            .onAppear {
                guard !didInitialize else { return }
                didInitialize = true
                
                // Do initial setup
                setupPhysicalController()
                loadAllButtonLayouts()
                
                // Load any PNG data for both orientations
                importedPNGDataLandscape = loadPNG(key: "importedPNGLandscape")
                importedPNGDataPortrait  = loadPNG(key: "importedPNGPortrait")
            }
            // When the user truly leaves, remove the controller observers
            .onDisappear {
                stopListeningForPhysicalControllers()
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Toggle("Auto Sprint", isOn: $isAutoSprintEnabled)
                            .onChange(of: isAutoSprintEnabled) { enabled in
                                handleAutoSprintToggle(enabled: enabled)
                            }
                        
                        Button {
                            isCreditsPresented.toggle()
                        } label: {
                            Label("Credits", systemImage: "info.circle")
                        }
                        
                        // Toggle editing; if we finish editing, save
                        Button {
                            isEditingLayout.toggle()
                            if !isEditingLayout {
                                saveCurrentOrientationLayout()
                            }
                        } label: {
                            Label("Customize Layout", systemImage: "rectangle.angledperson.fill")
                        }
                        
                        // Reset current orientation
                        Button("Reset Layout (Current)") {
                            resetToDefaultLayoutCurrent()
                            saveCurrentOrientationLayout()
                        }
                        
                        Divider()
                        
                        // Import PNG for each orientation
                        Button("Import PNG (Landscape)") {
                            showingFileImporterLandscape = true
                        }
                        Button("Import PNG (Portrait)") {
                            showingFileImporterPortrait = true
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            showQuitConfirmation = true
                        } label: {
                            Label("Quit", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 24, weight: .bold))
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
                Button("Cancel", role: .cancel) { }
            }
            // File importers
            .fileImporter(
                isPresented: $showingFileImporterLandscape,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        do {
                            let data = try Data(contentsOf: url)
                            savePNG(data: data, key: "importedPNGLandscape")
                            importedPNGDataLandscape = data
                            print("DEBUG: Imported PNG (landscape) from \(url).")
                        } catch {
                            print("ERROR: Could not read PNG data -> \(error.localizedDescription)")
                        }
                    } else {
                        print("ERROR: Could not access security scoped resource.")
                    }
                case .failure(let error):
                    print("ERROR: File import failed -> \(error.localizedDescription)")
                }
            }
            .fileImporter(
                isPresented: $showingFileImporterPortrait,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        do {
                            let data = try Data(contentsOf: url)
                            savePNG(data: data, key: "importedPNGPortrait")
                            importedPNGDataPortrait = data
                            print("DEBUG: Imported PNG (portrait) from \(url).")
                        } catch {
                            print("ERROR: Could not read PNG data -> \(error.localizedDescription)")
                        }
                    } else {
                        print("ERROR: Could not access security scoped resource.")
                    }
                case .failure(let error):
                    print("ERROR: File import failed -> \(error.localizedDescription)")
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Orientation-Specific Layout Persistence
extension EmulatorView {
    
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
                CustomButton(label: "Up",     keyCode: 38, x:  80, y:  80, width: 60, height: 60),
                CustomButton(label: "Down",   keyCode: 40, x:  80, y: 200, width: 60, height: 60),
                CustomButton(label: "Left",   keyCode: 37, x:  20, y: 140, width: 60, height: 60),
                CustomButton(label: "Right",  keyCode: 39, x: 140, y: 140, width: 60, height: 60),
                CustomButton(label: "A",      keyCode: 65, x: 240, y: 140, width: 60, height: 60),
                CustomButton(label: "B",      keyCode: 66, x: 300, y: 140, width: 60, height: 60),
                CustomButton(label: "Start",  keyCode: 32, x: 200, y: 250, width: 60, height: 60),
                CustomButton(label: "Select", keyCode: 83, x: 280, y: 250, width: 60, height: 60),
                CustomButton(label: "Reset",  keyCode: 82, x: 360, y: 250, width: 60, height: 60)
            ]
        } else {
            customButtonsLandscape = [
                CustomButton(label: "Up",     keyCode: 38, x: 100, y:  40, width: 60, height: 60),
                CustomButton(label: "Down",   keyCode: 40, x: 100, y: 160, width: 60, height: 60),
                CustomButton(label: "Left",   keyCode: 37, x:  40, y: 100, width: 60, height: 60),
                CustomButton(label: "Right",  keyCode: 39, x: 160, y: 100, width: 60, height: 60),
                CustomButton(label: "A",      keyCode: 65, x: 600, y:  80, width: 60, height: 60),
                CustomButton(label: "B",      keyCode: 66, x: 540, y: 100, width: 60, height: 60),
                CustomButton(label: "Start",  keyCode: 32, x: 300, y:  70, width: 60, height: 60),
                CustomButton(label: "Select", keyCode: 83, x: 360, y:  70, width: 60, height: 60),
                CustomButton(label: "Reset",  keyCode: 82, x: 300, y: 120, width: 60, height: 60)
            ]
        }
    }
    
    private func saveButtonArray(_ array: [CustomButton], key: String) {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(array)
            UserDefaults.standard.set(data, forKey: key)
            print("DEBUG: \(key) saved successfully.")
        } catch {
            print("ERROR: Failed to save \(key) - \(error.localizedDescription)")
        }
    }
    
    private func loadButtonArray(key: String) -> [CustomButton]? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            print("DEBUG: No saved layout found for \(key)")
            return nil
        }
        let decoder = JSONDecoder()
        do {
            let loadedButtons = try decoder.decode([CustomButton].self, from: data)
            print("DEBUG: Loaded layout for \(key).")
            return loadedButtons
        } catch {
            print("ERROR: Failed to load \(key) - \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - PNG Import Helpers
extension EmulatorView {
    private func savePNG(data: Data, key: String) {
        UserDefaults.standard.set(data, forKey: key)
        print("DEBUG: Custom PNG (\(key)) saved to UserDefaults.")
    }
    
    private func loadPNG(key: String) -> Data? {
        if let data = UserDefaults.standard.data(forKey: key) {
            print("DEBUG: Loaded custom PNG from key: \(key).")
            return data
        }
        return nil
    }
}

// MARK: - Physical Controller Setup
extension EmulatorView {
    private func setupPhysicalController() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { _ in
            configurePhysicalControllers()
        }
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { _ in
            // optional: handle disconnection
        }
        
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
                self.handleGamepadInput(gamepad, webView: webView)
            }
        }
    }
    
    private func handleGamepadInput(_ gamepad: GCExtendedGamepad, webView: WKWebView) {
        handleDirectionPad(gamepad.dpad, webView: webView)
        mapButton(gamepad.buttonA, keyCode: 65, webView: webView)
        let bKeyCode = isAutoSprintEnabled ? 0 : 66
        mapButton(gamepad.buttonB, keyCode: bKeyCode, webView: webView)
    }
    
    private func handleDirectionPad(_ dpad: GCControllerDirectionPad, webView: WKWebView) {
        mapButton(dpad.up,    keyCode: 38, webView: webView)
        mapButton(dpad.down,  keyCode: 40, webView: webView)
        mapButton(dpad.left,  keyCode: 37, webView: webView)
        mapButton(dpad.right, keyCode: 39, webView: webView)
        
        // Automatic sprint if enabled
        if isAutoSprintEnabled {
            if dpad.left.isPressed || dpad.right.isPressed {
                sendKeyPress(keyCode: 66, webView: webView)
            } else {
                sendKeyUp(keyCode: 66, webView: webView)
            }
        }
    }
    
    private func mapButton(_ button: GCControllerButtonInput, keyCode: Int, webView: WKWebView) {
        guard keyCode > 0 else { return }
        
        if button.isPressed {
            sendKeyPress(keyCode: keyCode, webView: webView)
        } else {
            sendKeyUp(keyCode: keyCode, webView: webView)
        }
    }
}

// MARK: - Keyboard JS Injection
extension EmulatorView {
    private func eventProperties(for keyCode: Int) -> (String, String) {
        switch keyCode {
            case 37: return ("ArrowLeft",  "ArrowLeft")
            case 38: return ("ArrowUp",    "ArrowUp")
            case 39: return ("ArrowRight", "ArrowRight")
            case 40: return ("ArrowDown",  "ArrowDown")
            case 32: return ("Space",      " ")
            case 65: return ("KeyA",       "a")
            case 66: return ("KeyB",       "b")
            case 82: return ("KeyR",       "r")
            case 83: return ("KeyS",       "s")
            default: return ("", "")
        }
    }
    
    private func sendKeyPress(keyCode: Int, webView: WKWebView?) {
        guard let webView = webView else {
            print("ERROR: WebView is nil. Cannot send key press for \(keyCode)")
            return
        }
        provideHapticFeedback()
        let (codeValue, keyValue) = eventProperties(for: keyCode)
        
        let jsCode = """
        (function() {
            var event = new KeyboardEvent('keydown', {
                bubbles: true,
                cancelable: true,
                code: '\(codeValue)',
                key: '\(keyValue)',
                keyCode: \(keyCode),
                which: \(keyCode)
            });
            document.dispatchEvent(event);
        })();
        """
        webView.evaluateJavaScript(jsCode, completionHandler: nil)
    }
    
    private func sendKeyUp(keyCode: Int, webView: WKWebView?) {
        guard let webView = webView else {
            print("ERROR: WebView is nil. Cannot send key up for \(keyCode)")
            return
        }
        provideHapticFeedback()
        let (codeValue, keyValue) = eventProperties(for: keyCode)
        
        let jsCode = """
        (function() {
            var event = new KeyboardEvent('keyup', {
                bubbles: true,
                cancelable: true,
                code: '\(codeValue)',
                key: '\(keyValue)',
                keyCode: \(keyCode),
                which: \(keyCode)
            });
            document.dispatchEvent(event);
        })();
        """
        webView.evaluateJavaScript(jsCode, completionHandler: nil)
    }
    
    private func provideHapticFeedback() {
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.impactOccurred()
    }
}

// MARK: - Auto Sprint
extension EmulatorView {
    private func handleAutoSprintToggle(enabled: Bool) {
        guard let webView = webViewModel.webView else {
            print("ERROR: WebView is nil. Cannot handle Auto Sprint toggle.")
            return
        }
        if enabled {
            autoSprintCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    self.sendKeyPress(keyCode: 66, webView: webView)
                }
            print("DEBUG: Auto Sprint enabled.")
        } else {
            autoSprintCancellable?.cancel()
            sendKeyUp(keyCode: 66, webView: webView)
            print("DEBUG: Auto Sprint disabled.")
        }
    }
    
    private func quitGame() {
        dismiss()
        print("DEBUG: Quit game triggered.")
    }
}

// MARK: - CreditsView
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
                Button(action: {
                    dismiss()
                }) {
                    Text("Close")
                        .font(.body)
                        .foregroundColor(.blue)
                        .padding()
                }
            }
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - NESWebView
struct NESWebView: UIViewRepresentable {
    let game: String
    @ObservedObject var webViewModel: WebViewModel
    
    func makeUIView(context: Context) -> WKWebView {
        // If we don't already have a WKWebView, create one
        if webViewModel.webView == nil {
            let newWebView = WKWebView()
            webViewModel.webView = newWebView
            
            // Load the game only once
            if let url = URL(string: "http://127.0.0.1:8080/index.html?rom=\(game)") {
                newWebView.load(URLRequest(url: url))
                print("DEBUG: Loaded game: \(game)")
            } else {
                print("ERROR: Invalid game URL.")
            }
        }
        return webViewModel.webView!
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Don't reload or recreate on orientation changes
    }
}

// MARK: - WebViewModel
class WebViewModel: ObservableObject {
    @Published var webView: WKWebView?
}

// MARK: - CustomButton
struct CustomButton: Identifiable, Codable {
    let id: UUID
    let label: String
    let keyCode: Int
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    
    init(id: UUID = UUID(),
         label: String,
         keyCode: Int,
         x: CGFloat,
         y: CGFloat,
         width: CGFloat,
         height: CGFloat) {
        self.id = id
        self.label = label
        self.keyCode = keyCode
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - DraggableButtonAreaView
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
                            .onChanged { value in
                                let deltaW = value.translation.width
                                let deltaH = value.translation.height
                                
                                let newWidth = max(minButtonSize, currentWidth + deltaW)
                                let newHeight = max(minButtonSize, currentHeight + deltaH)
                                
                                if button.x + newWidth <= screenSize.width {
                                    button.width = newWidth
                                }
                                if button.y + newHeight <= screenSize.height {
                                    button.height = newHeight
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
            x: min(
                max(button.x + dragOffset.width, button.width / 2),
                screenSize.width - button.width / 2
            ),
            y: min(
                max(button.y + dragOffset.height, button.height / 2),
                screenSize.height - button.height / 2
            )
        )
        .gesture(
            isEditing
                ? DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        button.x = min(
                            max(button.x + value.translation.width, button.width / 2),
                            screenSize.width - button.width / 2
                        )
                        button.y = min(
                            max(button.y + value.translation.height, button.height / 2),
                            screenSize.height - button.height / 2
                        )
                        dragOffset = .zero
                    }
                : DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        // Press
                        pressHandler(button.keyCode)
                    }
                    .onEnded { _ in
                        // Release
                        releaseHandler(button.keyCode)
                    }
        )
        .onAppear {
            currentWidth = button.width
            currentHeight = button.height
        }
    }
}

// MARK: - PNGOverlay
struct PNGOverlay: View {
    let pressHandler: (Int) -> Void
    let releaseHandler: (Int) -> Void
    let isEditing: Bool
    
    @Binding var buttons: [CustomButton]
    let importedPNGData: Data?
    
    var body: some View {
        GeometryReader { geometry in
            let screenSize = geometry.size
            
            ZStack {
                // Show PNG if available
                if let data = importedPNGData,
                   let uiImage = UIImage(data: data) {
                    
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: screenSize.width, height: screenSize.height)
                    
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: screenSize.width, height: screenSize.height)
                    
                    Text("No PNG Imported")
                        .foregroundColor(.white)
                }
                
                // Draggable button overlays
                ForEach($buttons) { $button in
                    DraggableButtonAreaView(
                        button: $button,
                        isEditing: isEditing,
                        screenSize: screenSize,
                        pressHandler: pressHandler,
                        releaseHandler: releaseHandler
                    )
                }
            }
        }
    }
}
