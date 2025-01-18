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
                            Label("Customize Layout", systemImage: "rectangle.angledperson.fill")
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
        webViewModel.webView = webView
        
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
    
    private let defaultSVGString: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" version="1.1" width="812" height="375" viewBox="0 0 812 375">
      <defs>
        <clipPath id="clip_0">
          <path transform="matrix(1,0,0,-1,0,375)" d="M0 375H812V0H0Z"></path>
        </clipPath>
      </defs>
      <g>
        <g inkscape:groupmode="layer" inkscape:label="Layer 1">
          <g clip-path="url(#clip_0)">
            <path transform="matrix(1,0,0,-1,429.5615,16.00119)" d="M0 0-47.298-.047C-53.786-.095-59.026-5.413-58.978-11.901-58.93-18.391-53.611-23.63-47.123-23.582L.175-23.535C6.663-23.486 11.903-18.169 11.854-11.68 11.807-5.191 6.489 .049 0 0" fill="#444444"></path>
            <path transform="matrix(1,0,0,-1,429.6494,17.000214)" d="M0 0H-.08L-47.385-.048C-50.249-.069-52.943-1.211-54.965-3.262-56.986-5.313-58.087-8.024-58.065-10.896-58.044-13.767-56.903-16.461-54.852-18.481-52.819-20.483-50.141-21.584-47.3-21.584-47.272-21.584-47.245-21.583-47.219-21.583L.086-21.536C2.95-21.515 5.645-20.373 7.666-18.321 9.688-16.271 10.788-13.56 10.767-10.688 10.723-4.778 5.9 0 0 0M-47.306-23.584C-50.67-23.584-53.847-22.28-56.255-19.906-58.688-17.511-60.04-14.315-60.065-10.91-60.091-7.505-58.785-4.29-56.39-1.858-53.993 .573-50.799 1.927-47.394 1.952L-.093 2H0C6.997 2 12.715-3.665 12.767-10.674 12.792-14.079 11.486-17.293 9.091-19.726 6.694-22.157 3.5-23.511 .095-23.536L-47.21-23.583C-47.242-23.583-47.274-23.584-47.306-23.584" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,389.8535,32.174989)" d="M0 0V8.278H2.043L4.332 2.714H4.436L6.73 8.278H8.767V0H7.16V5.536H7.068L4.963 .476H3.81L1.698 5.536H1.606V0Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,405.7842,32.174989)" d="M0 0H-5.485V8.278H0V6.799H-3.753V4.865H-.213V3.494H-3.753V1.48H0Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,407.2793,32.174989)" d="M0 0V8.278H1.446L5.256 3.121H5.358V8.278H7.017V0H5.582L1.762 5.181H1.658V0Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,417.7256,29.139893)" d="M0 0C0-1.045 .625-1.71 1.732-1.71 2.846-1.71 3.471-1.045 3.471 0V5.243H5.204V-.178C5.204-2.014 3.855-3.248 1.732-3.248-.385-3.248-1.732-2.014-1.732-.178V5.243H0Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,383.0986,335.4172)" d="M0 0-47.298-.048C-53.786-.096-59.026-5.414-58.979-11.902-58.931-18.392-53.612-23.631-47.123-23.583L.174-23.536C6.663-23.487 11.902-18.17 11.854-11.681 11.807-5.192 6.488 .048 0 0" fill="#444444"></path>
            <path transform="matrix(1,0,0,-1,383.1895,336.4182)" d="M0 0H-.083L-47.388-.047C-50.252-.068-52.946-1.209-54.968-3.261-56.988-5.312-58.09-8.023-58.068-10.895-58.047-13.766-56.906-16.46-54.854-18.481-52.823-20.483-50.145-21.582-47.305-21.582H-47.222L.083-21.535C2.947-21.514 5.642-20.373 7.663-18.321 9.685-16.27 10.786-13.559 10.765-10.688 10.743-7.816 9.602-5.122 7.55-3.101 5.519-1.099 2.84 0 0 0M-47.311-23.582C-50.674-23.582-53.85-22.279-56.258-19.906-58.69-17.51-60.043-14.314-60.068-10.91-60.094-7.504-58.788-4.289-56.393-1.857-53.996 .575-50.802 1.928-47.396 1.953L-.096 2H0C3.369 2 6.545 .697 8.954-1.676 11.386-4.072 12.739-7.268 12.765-10.673 12.816-17.714 7.131-23.483 .092-23.535L-47.213-23.582Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,339.4023,349.0002)" d="M0 0C.078-.655 .739-1.075 1.69-1.075 2.569-1.075 3.191-.65 3.191-.04 3.191 .476 2.788 .772 1.798 .985L.745 1.209C-.728 1.518-1.449 2.285-1.449 3.517-1.449 5.039-.223 6.041 1.642 6.041 3.422 6.04 4.682 5.044 4.731 3.604L3.142 3.605C3.063 4.243 2.47 4.669 1.652 4.669 .808 4.669 .247 4.277 .247 3.662 .247 3.163 .634 2.878 1.579 2.676L2.554 2.469C4.177 2.127 4.877 1.427 4.877 .173 4.876-1.456 3.628-2.453 1.601-2.452-.325-2.452-1.573-1.506-1.635 .001Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,351.1113,351.2473)" d="M0 0-5.352 .001-5.351 8.08 .002 8.079V6.634L-3.66 6.635V4.748L-.206 4.747V3.409L-3.66 3.41-3.661 1.445 .001 1.444Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,358.0625,351.2492)" d="M0 0-5.285 .001-5.283 8.08H-3.593L-3.594 1.474 0 1.473Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,364.835,351.2502)" d="M0 0-5.353 .001-5.351 8.08 .001 8.079V6.635H-3.66L-3.661 4.748H-.206L-.207 3.409-3.661 3.41V1.445L0 1.444Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,366.1426,347.2082)" d="M0 0C.001 2.626 1.445 4.243 3.791 4.243 5.706 4.242 7.173 2.972 7.296 1.213L5.649 1.214C5.487 2.143 4.754 2.754 3.791 2.754 2.521 2.754 1.73 1.701 1.73-.001 1.729-1.702 2.52-2.761 3.796-2.761 4.765-2.762 5.492-2.19 5.654-1.3L7.301-1.301C7.16-3.047 5.738-4.251 3.79-4.25 1.449-4.25 0-2.632 0 0" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,376.6758,351.2531)" d="M0 0 .002 6.635-2.423 6.636V8.08L4.117 8.078 4.116 6.634 1.692 6.635 1.691 0Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,476.0244,335.4152)" d="M0 0-47.298-.047C-53.786-.096-59.026-5.414-58.979-11.902-58.931-18.391-53.612-23.631-47.123-23.583L.174-23.535C6.663-23.487 11.902-18.169 11.854-11.681 11.807-5.191 6.488 .048 0 0" fill="#444444"></path>
            <path transform="matrix(1,0,0,-1,476.1123,336.4152)" d="M0 0H-.08L-47.385-.048C-50.249-.069-52.943-1.21-54.965-3.262-56.986-5.313-58.087-8.024-58.065-10.895-58.044-13.767-56.903-16.461-54.852-18.481-52.819-20.483-50.141-21.583-47.3-21.583H-47.219L.086-21.535C6.017-21.491 10.812-16.625 10.768-10.688 10.723-4.778 5.9 0 0 0M-47.306-23.583C-50.67-23.583-53.847-22.28-56.255-19.906-58.688-17.511-60.04-14.315-60.065-10.91-60.091-7.505-58.785-4.29-56.39-1.858-53.993 .574-50.798 1.927-47.394 1.952L-.093 2H0C6.997 2 12.715-3.665 12.768-10.673 12.819-17.714 7.134-23.483 .095-23.535L-47.21-23.583Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,435.707,349.0022)" d="M0 0C.078-.654 .739-1.074 1.691-1.073 2.57-1.073 3.191-.647 3.19-.037 3.19 .478 2.787 .774 1.796 .986L.743 1.21C-.729 1.518-1.452 2.284-1.452 3.516-1.453 5.038-.228 6.041 1.637 6.042 3.417 6.043 4.677 5.048 4.729 3.608L3.139 3.607C3.06 4.246 2.466 4.671 1.648 4.671 .803 4.67 .243 4.278 .244 3.662 .244 3.164 .631 2.878 1.577 2.678L2.551 2.471C4.175 2.13 4.875 1.431 4.876 .177 4.877-1.452 3.629-2.45 1.603-2.451-.324-2.452-1.573-1.507-1.636-.001Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,444.0244,351.2424)" d="M0 0-.004 6.635-2.428 6.633-2.429 8.078 4.11 8.081 4.111 6.637 1.687 6.636 1.691 .001Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,450.7549,348.008)" d="M0 0 2.117 .001 1.113 3.17H1.012ZM2.476-1.303-.362-1.305-.983-3.231-2.68-3.232 .121 4.849 2.108 4.85 4.918-3.228 3.087-3.229Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,458.624,347.007)" d="M0 0 1.483 .001C2.335 .001 2.833 .461 2.832 1.239 2.832 2.006 2.306 2.487 1.466 2.486H-.001ZM.003-4.227-1.688-4.228-1.692 3.851 1.7 3.853C3.475 3.854 4.567 2.869 4.568 1.263 4.568 .232 4.031-.664 3.103-1.034L4.807-4.225 2.892-4.226 1.384-1.298 .001-1.299Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,466.7422,351.2297)" d="M0 0-.004 6.635-2.428 6.634-2.429 8.078 4.11 8.082 4.111 6.637 1.687 6.636 1.69 .001Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,745.0312,221.883)" d="M0 0C19.782 0 35.818-16.099 35.818-35.957 35.818-55.814 19.782-71.913 0-71.913-19.782-71.913-35.819-55.814-35.819-35.957-35.819-16.099-19.782 0 0 0" fill="#b71111"></path>
            <path transform="matrix(1,0,0,-1,745.0312,223.0334)" d="M0 0C-19.116 0-34.669-15.614-34.669-34.807-34.669-53.999-19.116-69.612 0-69.612 19.116-69.612 34.668-53.999 34.668-34.807 34.668-15.614 19.116 0 0 0M0-71.913C-20.385-71.913-36.969-55.268-36.969-34.807-36.969-14.346-20.385 2.3 0 2.3 20.385 2.3 36.969-14.346 36.969-34.807 36.969-55.268 20.385-71.913 0-71.913" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,748.335,260.0022)" d="M0 0C-1.682 5.413-2.629 8.474-2.84 9.184-3.052 9.894-3.203 10.454-3.296 10.865-3.673 9.4-4.755 5.778-6.54 0ZM3.09-10.438 1.271-4.464H-7.879L-9.698-10.438H-15.432L-6.574 14.763H-.068L8.824-10.438Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,680.0312,286.883)" d="M0 0C19.782 0 35.819-16.099 35.819-35.957 35.819-55.814 19.782-71.913 0-71.913-19.781-71.913-35.818-55.814-35.818-35.957-35.818-16.099-19.781 0 0 0" fill="#b71111"></path>
            <path transform="matrix(1,0,0,-1,680.0312,288.0334)" d="M0 0C-19.116 0-34.668-15.614-34.668-34.807-34.668-53.999-19.116-69.612 0-69.612 19.116-69.612 34.669-53.999 34.669-34.807 34.669-15.614 19.116 0 0 0M0-71.913C-20.385-71.913-36.969-55.268-36.969-34.807-36.969-14.346-20.385 2.3 0 2.3 20.385 2.3 36.969-14.346 36.969-34.807 36.969-55.268 20.385-71.913 0-71.913" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,676.0488,324.4533)" d="M0 0V-6.54H3.468C4.933-6.54 6.015-6.26 6.712-5.699 7.41-5.139 7.76-4.28 7.76-3.124 7.76-1.041 6.272 0 3.296 0ZM0 4.223H3.09C4.532 4.223 5.576 4.446 6.223 4.893 6.87 5.339 7.193 6.077 7.193 7.106 7.193 8.068 6.841 8.758 6.138 9.176 5.433 9.593 4.32 9.802 2.799 9.802H0ZM-5.321 14.162H2.489C6.049 14.162 8.632 13.655 10.239 12.644 11.848 11.63 12.651 10.019 12.651 7.811 12.651 6.312 12.299 5.081 11.597 4.12 10.892 3.158 9.957 2.581 8.789 2.386V2.215C10.38 1.86 11.528 1.195 12.23 .224 12.936-.749 13.287-2.043 13.287-3.656 13.287-5.945 12.46-7.73 10.807-9.012 9.153-10.294 6.907-10.935 4.068-10.935H-5.321Z" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,46.5752,256.8332)" d="M0 0C-8.45 0-15.325-6.876-15.325-15.327V-38.183C-15.325-46.623-8.45-53.489 0-53.489H33.105V-86.592C33.105-95.042 39.979-101.917 48.43-101.917H71.268C79.718-101.917 86.592-95.042 86.592-86.592V-53.489H119.695C128.134-53.489 134.999-46.623 134.999-38.183V-15.327C134.999-6.876 128.134 0 119.695 0H86.592V33.103C86.592 41.542 79.718 48.407 71.268 48.407H48.43C39.979 48.407 33.105 41.542 33.105 33.103V0Z" fill="#444444"></path>
            <path transform="matrix(1,0,0,-1,46.5742,258.0822)" d="M0 0C-7.761 0-14.074-6.316-14.074-14.079V-36.934C-14.074-44.685-7.761-50.99 0-50.99H33.105L34.355-52.24V-85.344C34.355-93.104 40.67-99.418 48.431-99.418H71.269C79.03-99.418 85.344-93.104 85.344-85.344V-52.24L86.594-50.99H119.696C127.445-50.99 133.75-44.685 133.75-36.934V-14.079C133.75-6.316 127.445 0 119.696 0H86.594L85.344 1.25V34.352C85.344 42.102 79.03 48.406 71.269 48.406H48.431C40.67 48.406 34.355 42.102 34.355 34.352V1.25L33.105 0ZM71.269-101.918H48.431C39.291-101.918 31.855-94.482 31.855-85.344V-53.49H0C-9.139-53.49-16.574-46.063-16.574-36.934V-14.079C-16.574-4.937-9.139 2.5 0 2.5H31.855V34.352C31.855 43.479 39.291 50.906 48.431 50.906H71.269C80.408 50.906 87.844 43.479 87.844 34.352V2.5H119.696C128.825 2.5 136.25-4.937 136.25-14.079V-36.934C136.25-46.063 128.825-53.49 119.696-53.49H87.844V-85.344C87.844-94.482 80.408-101.918 71.269-101.918" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,106.4131,268.1682)" d="M0 0C-8.502 0-15.419-6.917-15.419-15.419-15.419-23.921-8.502-30.838 0-30.838 8.502-30.838 15.42-23.921 15.42-15.419 15.42-6.917 8.502 0 0 0M0-33.516C-9.979-33.516-18.097-25.397-18.097-15.419-18.097-5.44-9.979 2.678 0 2.678 9.979 2.678 18.097-5.44 18.097-15.419 18.097-25.397 9.979-33.516 0-33.516" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,117.9629,243.4299)" d="M0 0C-.343 0-.686 .131-.946 .393L-11.55 10.995-22.152 .393C-22.675-.131-23.522-.131-24.045 .393-24.568 .915-24.568 1.763-24.045 2.285L-12.496 13.835C-11.973 14.357-11.126 14.357-10.603 13.835L.946 2.285C1.47 1.763 1.47 .915 .946 .393 .685 .131 .343 0 0 0" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,147.9092,296.4748)" d="M0 0C-.343 0-.685 .131-.946 .392-1.47 .915-1.47 1.763-.946 2.285L9.656 12.888-.946 23.49C-1.47 24.014-1.47 24.861-.946 25.384-.424 25.906 .424 25.906 .946 25.384L12.496 13.834C12.758 13.573 12.889 13.23 12.889 12.888 12.889 12.545 12.758 12.202 12.496 11.941L.946 .392C.686 .131 .343 0 0 0" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,106.4131,337.9709)" d="M0 0C-.342 0-.685 .131-.946 .392L-12.495 11.941C-13.019 12.464-13.019 13.312-12.495 13.834-11.973 14.357-11.125 14.357-10.603 13.834L0 3.231 10.604 13.834C11.126 14.357 11.974 14.357 12.496 13.834 13.02 13.312 13.02 12.464 12.496 11.941L.947 .392C.686 .131 .343 0 0 0" fill="#dddddd"></path>
            <path transform="matrix(1,0,0,-1,64.917,296.4748)" d="M0 0C-.342 0-.685 .131-.946 .392L-12.495 11.941C-12.757 12.202-12.888 12.545-12.888 12.888-12.888 13.23-12.757 13.573-12.495 13.834L-.946 25.384C-.423 25.906 .424 25.906 .947 25.384 1.47 24.861 1.47 24.014 .947 23.49L-9.656 12.888 .947 2.285C1.47 1.763 1.47 .915 .947 .392 .686 .131 .343 0 0 0" fill="#dddddd"></path>
          </g>
        </g>
      </g>
    </svg>

    """
    
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
