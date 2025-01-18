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
import SVGView
import UniformTypeIdentifiers
import UIKit


// MARK: - EmulatorView
struct EmulatorView: View {
    let game: String
    
    @StateObject private var webViewModel = WebViewModel()
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("isAutoSprintEnabled") private var isAutoSprintEnabled = false
    
    @State private var autoSprintCancellable: AnyCancellable?
    @State private var isCreditsPresented = false
    @State private var showQuitConfirmation = false
    @State private var isEditingLayout = false
    @State private var showingFileImporter = false
    @State private var importedSVGData: Data? = nil
    
    // MARK: - NES-Style Buttons
    @State private var customButtons: [CustomButton] = [
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
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                GeometryReader { geometry in
                    ZStack {
                        NESWebView(game: game, webViewModel: webViewModel)
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height * 0.90
                            )
                            .position(
                                x: geometry.size.width / 2,
                                y: geometry.size.height * 0.46
                            )
                            .onAppear {
                                setupPhysicalController()
                                loadButtonLayout()
                                if let savedSVG = loadCustomSVG() {
                                    importedSVGData = savedSVG
                                }
                            }
                            .onDisappear {
                                stopListeningForPhysicalControllers()
                            }
                        
                        SVGOverlay(
                            pressHandler: { keyCode in
                                guard keyCode > 0 else { return }
                                sendKeyPress(keyCode: keyCode, webView: webViewModel.webView)
                            },
                            releaseHandler: { keyCode in
                                guard keyCode > 0 else { return }
                                sendKeyUp(keyCode: keyCode, webView: webViewModel.webView)
                            },
                            isEditing: isEditingLayout,
                            buttons: $customButtons,
                            importedSVGData: importedSVGData
                        )
                        .edgesIgnoringSafeArea(.all)
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
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
                        
                        Button {
                            isEditingLayout.toggle()
                            if !isEditingLayout {
                                // Save layout after finishing edit
                                saveButtonLayout()
                            }
                        } label: {
                            Label("Customize Layout", systemImage: "person.crop.rectangle.fill")
                        }
                        
                        Button("Reset Layout") {
                            resetToDefaultLayout()
                            saveButtonLayout()
                        }
                        
                        Divider()
                        
                        Button("Import SVG") {
                            showingFileImporter = true
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
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [
                    .image
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    // Access security scoped resource
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() } // Ensure resource access is stopped
                        do {
                            let data = try Data(contentsOf: url)
                            saveCustomSVG(data: data)
                            importedSVGData = data
                            print("DEBUG: Imported SVG from \(url).")
                        } catch {
                            print("ERROR: Could not read SVG data -> \(error.localizedDescription)")
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

// MARK: - Import/Export Helpers
extension EmulatorView {
    
    private func saveCustomSVG(data: Data) {
        UserDefaults.standard.set(data, forKey: "importedSVG")
        print("DEBUG: Custom SVG saved to UserDefaults.")
    }
    
    private func loadCustomSVG() -> Data? {
        if let data = UserDefaults.standard.data(forKey: "importedSVG") {
            print("DEBUG: Loaded custom SVG from UserDefaults.")
            return data
        }
        return nil
    }
}

// MARK: - Button Layout Persistence
extension EmulatorView {
    
    private func saveButtonLayout() {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(customButtons)
            UserDefaults.standard.set(data, forKey: "buttonLayout")
            print("DEBUG: Button layout saved successfully.")
        } catch {
            print("ERROR: Failed to save button layout - \(error.localizedDescription)")
        }
    }
    
    private func loadButtonLayout() {
        guard let data = UserDefaults.standard.data(forKey: "buttonLayout") else {
            print("DEBUG: No saved layout found.")
            return
        }
        
        let decoder = JSONDecoder()
        do {
            let loadedButtons = try decoder.decode([CustomButton].self, from: data)
            self.customButtons = loadedButtons
            print("DEBUG: Loaded saved button layout.")
        } catch {
            print("ERROR: Failed to load button layout - \(error.localizedDescription)")
        }
    }
    
    private func resetToDefaultLayout() {
        customButtons = [
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

// MARK: - Physical Controller Setup
extension EmulatorView {
    
    @MainActor
    private func setupPhysicalController() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await configurePhysicalControllers()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { _ in
            // optional disconnection logic
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
        provideHapticFeedback() // Haptic feedback on key press
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
        provideHapticFeedback() // Haptic feedback on key release
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
        let webView = WKWebView()
        DispatchQueue.main.async {
            webViewModel.webView = webView
        }
        
        if let url = URL(string: "http://127.0.0.1:8080/index.html?rom=\(game)") {
            webView.load(URLRequest(url: url))
            print("DEBUG: Loaded game: \(game)")
        } else {
            print("ERROR: Invalid game URL.")
        }
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}

// MARK: - WebViewModel
@MainActor
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
            x: min(max(button.x + dragOffset.width, button.width / 2),
                   screenSize.width - button.width / 2),
            y: min(max(button.y + dragOffset.height, button.height / 2),
                   screenSize.height - button.height / 2)
        )
        .gesture(
            isEditing
                ? DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        button.x = min(max(button.x + value.translation.width, button.width / 2),
                                       screenSize.width - button.width / 2)
                        button.y = min(max(button.y + value.translation.height, button.height / 2),
                                       screenSize.height - button.height / 2)
                        dragOffset = .zero
                    }
                : DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        pressHandler(button.keyCode)
                    }
                    .onEnded { _ in
                        releaseHandler(button.keyCode)
                    }
        )
        .onAppear {
            currentWidth = button.width
            currentHeight = button.height
        }
    }
}

// MARK: - SVGOverlay
struct SVGOverlay: View {
    let pressHandler: (Int) -> Void
    let releaseHandler: (Int) -> Void
    let isEditing: Bool
    @Binding var buttons: [CustomButton]
    
    let importedSVGData: Data?
    
    private let defaultSVGString: String = try! String(contentsOf: Bundle.main.url(forResource: "default", withExtension: "svg")!, encoding: .utf8)
    var body: some View {
        GeometryReader { geometry in
            let screenSize = geometry.size
            
            ZStack {
                if let data = importedSVGData {
                    SVGView(data: data)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: screenSize.width, height: screenSize.height)
                }
                else if let data = defaultSVGString.data(using: .utf8) {
                    SVGView(data: data)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: screenSize.width, height: screenSize.height)
                } else {
                    Text("Failed to load SVG")
                        .foregroundColor(.red)
                }
                
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
