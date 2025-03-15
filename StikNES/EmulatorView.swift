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
import AVFoundation
import AVKit

// MARK: - AirPlay Views

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView(frame: .zero)
        routePickerView.activeTintColor = .blue
        routePickerView.tintColor = .gray
        return routePickerView
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct AirPlaySheetView: View {
    var body: some View {
        VStack {
            Text("Select AirPlay Device")
                .font(.headline)
                .padding()
            AirPlayButton()
                .frame(width: 44, height: 44)
            Spacer()
        }
        .padding()
    }
}

// MARK: - External Display

struct ExternalDisplayContentView: View {
    let game: String
    @ObservedObject var webViewModel: WebViewModel
    var body: some View {
        NESWebView(game: game, webViewModel: webViewModel)
            .edgesIgnoringSafeArea(.all)
    }
}

class ExternalDisplayManager: ObservableObject {
    @Published var externalScreenConnected: Bool = false
    var externalWindow: UIWindow?
    let game: String
    let webViewModel: WebViewModel
    
    init(game: String, webViewModel: WebViewModel) {
        self.game = game
        self.webViewModel = webViewModel
        NotificationCenter.default.addObserver(self, selector: #selector(screenDidConnect(notification:)), name: UIScreen.didConnectNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenDidDisconnect(notification:)), name: UIScreen.didDisconnectNotification, object: nil)
        updateScreenStatus()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func updateScreenStatus() {
        let hasExternal = UIScreen.screens.count > 1
        DispatchQueue.main.async {
            self.externalScreenConnected = hasExternal
            if hasExternal {
                if let externalScreen = UIScreen.screens.last, self.externalWindow == nil {
                    self.externalWindow = UIWindow(frame: externalScreen.bounds)
                    self.externalWindow?.screen = externalScreen
                    let externalView = ExternalDisplayContentView(game: self.game, webViewModel: self.webViewModel)
                    self.externalWindow?.rootViewController = UIHostingController(rootView: externalView)
                    self.externalWindow?.isHidden = false
                }
            } else {
                self.externalWindow?.isHidden = true
                self.externalWindow = nil
            }
        }
    }
    
    @objc func screenDidConnect(notification: Notification) {
        updateScreenStatus()
    }
    @objc func screenDidDisconnect(notification: Notification) {
        updateScreenStatus()
    }
}

// MARK: - Friendly Key Mapping

/// Maps user-friendly names (typed in the sheet) to numeric key codes.
private let friendlyToCode: [String: Int] = [
    "left": 37, "arrowleft": 37,
    "right": 39, "arrowright": 39,
    "up": 38, "arrowup": 38,
    "down": 40, "arrowdown": 40,
    "space": 32, " ": 32,
    "a": 65,
    "b": 66,
    "r": 82,
    "s": 83
]

/// Maps numeric codes back to a user-friendly name for display.
private let codeToFriendly: [Int: String] = [
    37: "Left",
    38: "Up",
    39: "Right",
    40: "Down",
    32: "Space",
    65: "A",
    66: "B",
    82: "R",
    83: "S"
]

/// Converts a typed string (e.g. "left") into a numeric code (e.g. 37).
private func parseFriendlyKey(_ input: String) -> Int? {
    friendlyToCode[input.lowercased()]
}

/// Returns a user-friendly name for a given numeric code (e.g. 37 -> "Left").
private func friendlyKeyName(for code: Int) -> String {
    codeToFriendly[code] ?? "\(code)"
}

// Default mappings by label (for the Reset All Keymap button)
private let defaultKeyMapping: [String: Int] = [
    "Up": 38,
    "Down": 40,
    "Left": 37,
    "Right": 39,
    "A": 65,
    "B": 66,
    "Start": 32,
    "Select": 83,
    "Reset": 82
]

// MARK: - Remap Key Sheet (Friendly)

struct RemapKeySheetView: View {
    @Binding var newKeyText: String
    var buttonLabel: String
    var onSave: () -> Void
    var onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Remap Key for \(buttonLabel)")) {
                    TextField("Enter key (e.g. A, B, Left, Up, Space)", text: $newKeyText)
                        .autocapitalization(.none)
                }
            }
            .navigationBarTitle("Remap Key", displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel", action: onCancel),
                                trailing: Button("Save", action: onSave))
        }
    }
}

// MARK: - EmulatorView

struct EmulatorView: View {
    let game: String
    
    @StateObject private var webViewModel: WebViewModel
    @StateObject private var externalDisplayManager: ExternalDisplayManager
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("isAutoSprintEnabled") private var isAutoSprintEnabled = false
    @AppStorage("isHapticFeedbackEnabled") private var isHapticFeedbackEnabled = false
    @AppStorage("isSkinVisible") private var isSkinVisible = true
    
    @State private var didInitialize = false
    @State private var autoSprintCancellable: AnyCancellable?
    @State private var isCreditsPresented = false
    @State private var showQuitConfirmation = false
    @State private var isEditingLayout = false
    @State private var showingPhotoPickerLandscape = false
    @State private var showingPhotoPickerPortrait = false
    @State private var selectedPhotoLandscape: PhotosPickerItem?
    @State private var selectedPhotoPortrait: PhotosPickerItem?
    @State private var isHelpDialogPresented = false
    @State private var showResetLayoutConfirmation = false
    @State private var showResetSkinsConfirmation = false
    @State private var showForceReloadConfirmation = false
    @State private var webViewRecoveryAttempts = 0
    
    // Confirmation for resetting all keymaps
    @State private var showResetKeymapConfirmation = false
    
    private let maxRecoveryAttempts = 3
    private let recoveryTimeout = 5.0
    @State private var showAirPlaySheet = false
    
    // Custom Buttons (Portrait)
    @State private var customButtonsPortrait: [CustomButton] = [
        CustomButton(label: "Up", keyCode: 38, x: UIScreen.main.bounds.width * 0.22, y: UIScreen.main.bounds.height * 0.12, width: 60, height: 60),
        CustomButton(label: "Down", keyCode: 40, x: UIScreen.main.bounds.width * 0.22, y: UIScreen.main.bounds.height * 0.25, width: 60, height: 60),
        CustomButton(label: "Left", keyCode: 37, x: UIScreen.main.bounds.width * 0.05, y: UIScreen.main.bounds.height * 0.185, width: 60, height: 60),
        CustomButton(label: "Right", keyCode: 39, x: UIScreen.main.bounds.width * 0.39, y: UIScreen.main.bounds.height * 0.185, width: 60, height: 60),
        CustomButton(label: "A", keyCode: 65, x: UIScreen.main.bounds.width * 0.82, y: UIScreen.main.bounds.height * 0.189, width: 60, height: 60),
        CustomButton(label: "B", keyCode: 66, x: UIScreen.main.bounds.width * 0.63, y: UIScreen.main.bounds.height * 0.189, width: 60, height: 60),
        CustomButton(label: "Start", keyCode: 32, x: UIScreen.main.bounds.width * 0.60, y: UIScreen.main.bounds.height * 0.32, width: 60, height: 60),
        CustomButton(label: "Select", keyCode: 83, x: UIScreen.main.bounds.width * 0.40, y: UIScreen.main.bounds.height * 0.32, width: 60, height: 60),
        CustomButton(label: "Reset", keyCode: 82, x: UIScreen.main.bounds.width * 0.05, y: UIScreen.main.bounds.height * 0.32, width: 60, height: 60)
    ]
    
    // Custom Buttons (Landscape)
    @State private var customButtonsLandscape: [CustomButton] = {
        let landscapeWidth = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let landscapeHeight = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        return [
            CustomButton(label: "Up", keyCode: 38, x: landscapeWidth * 0.13, y: landscapeHeight * 0.61, width: 60, height: 60),
            CustomButton(label: "Down", keyCode: 40, x: landscapeWidth * 0.13, y: landscapeHeight * 0.88, width: 60, height: 60),
            CustomButton(label: "Left", keyCode: 37, x: landscapeWidth * 0.06, y: landscapeHeight * 0.74, width: 60, height: 60),
            CustomButton(label: "Right", keyCode: 39, x: landscapeWidth * 0.20, y: landscapeHeight * 0.74, width: 60, height: 60),
            CustomButton(label: "A", keyCode: 65, x: landscapeWidth * 0.92, y: landscapeHeight * 0.67, width: 60, height: 60),
            CustomButton(label: "B", keyCode: 66, x: landscapeWidth * 0.84, y: landscapeHeight * 0.84, width: 60, height: 60),
            CustomButton(label: "Select", keyCode: 83, x: landscapeWidth * 0.44, y: landscapeHeight * 0.90, width: 60, height: 60),
            CustomButton(label: "Start", keyCode: 32, x: landscapeWidth * 0.56, y: landscapeHeight * 0.90, width: 60, height: 60),
            CustomButton(label: "Reset", keyCode: 82, x: landscapeWidth * 0.50, y: landscapeHeight * 0.04, width: 60, height: 60)
        ]
    }()
    
    @State private var importedPNGDataLandscape: Data? = nil
    @State private var importedPNGDataPortrait: Data? = nil
    @State private var activePresses = Set<Int>()
    @State private var reloadID = UUID()
    
    // Key remapping states
    @State private var remappingButton: CustomButton? = nil
    @State private var newKeyText: String = ""
    
    private var appDelegate: AppDelegate? {
        UIApplication.shared.delegate as? AppDelegate
    }
    
    private let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }()
    
    init(game: String) {
        self.game = game
        let webVM = WebViewModel()
        _webViewModel = StateObject(wrappedValue: webVM)
        _externalDisplayManager = StateObject(wrappedValue: ExternalDisplayManager(game: game, webViewModel: webVM))
    }
    
    var body: some View {
        Group {
            NavigationView {
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    GeometryReader { geometry in
                        let isPortrait = geometry.size.height > geometry.size.width
                        let displayedButtons = isPortrait ? $customButtonsPortrait : $customButtonsLandscape
                        let pngDataToUse = isPortrait ? importedPNGDataPortrait : importedPNGDataLandscape
                        
                        if externalDisplayManager.externalScreenConnected && isPortrait {
                            VStack(spacing: 0) {
                                Text("Emulator output is on the TV")
                                    .frame(width: geometry.size.width, height: geometry.size.height * 0.5)
                                    .foregroundColor(.white)
                                PNGOverlay(
                                    pressHandler: { keyCode in onScreenPress(keyCode: keyCode) },
                                    releaseHandler: { keyCode in onScreenRelease(keyCode: keyCode) },
                                    isEditing: isEditingLayout,
                                    buttons: displayedButtons,
                                    importedPNGData: pngDataToUse,
                                    isPortrait: true,
                                    remapHandler: { button in
                                        remappingButton = button
                                        newKeyText = friendlyKeyName(for: button.keyCode)
                                    }
                                )
                                .frame(width: geometry.size.width, height: geometry.size.height * 0.5)
                            }
                        }
                        else if externalDisplayManager.externalScreenConnected && !isPortrait {
                            ZStack {
                                Color.black
                                PNGOverlay(
                                    pressHandler: { keyCode in onScreenPress(keyCode: keyCode) },
                                    releaseHandler: { keyCode in onScreenRelease(keyCode: keyCode) },
                                    isEditing: isEditingLayout,
                                    buttons: displayedButtons,
                                    importedPNGData: pngDataToUse,
                                    isPortrait: false,
                                    remapHandler: { button in
                                        remappingButton = button
                                        newKeyText = friendlyKeyName(for: button.keyCode)
                                    }
                                )
                                .edgesIgnoringSafeArea(.all)
                            }
                        }
                        else {
                            // Normal local display
                            if isPortrait {
                                VStack(spacing: 0) {
                                    NESWebView(game: game, webViewModel: webViewModel)
                                        .frame(width: geometry.size.width, height: geometry.size.height * 0.5)
                                    PNGOverlay(
                                        pressHandler: { keyCode in onScreenPress(keyCode: keyCode) },
                                        releaseHandler: { keyCode in onScreenRelease(keyCode: keyCode) },
                                        isEditing: isEditingLayout,
                                        buttons: displayedButtons,
                                        importedPNGData: pngDataToUse,
                                        isPortrait: true,
                                        remapHandler: { button in
                                            remappingButton = button
                                            newKeyText = friendlyKeyName(for: button.keyCode)
                                        }
                                    )
                                    .frame(width: geometry.size.width, height: geometry.size.height * 0.5)
                                }
                            } else {
                                ZStack {
                                    NESWebView(game: game, webViewModel: webViewModel)
                                        .frame(width: geometry.size.width, height: geometry.size.height)
                                    PNGOverlay(
                                        pressHandler: { keyCode in onScreenPress(keyCode: keyCode) },
                                        releaseHandler: { keyCode in onScreenRelease(keyCode: keyCode) },
                                        isEditing: isEditingLayout,
                                        buttons: displayedButtons,
                                        importedPNGData: pngDataToUse,
                                        isPortrait: false,
                                        remapHandler: { button in
                                            remappingButton = button
                                            newKeyText = friendlyKeyName(for: button.keyCode)
                                        }
                                    )
                                    .edgesIgnoringSafeArea(.all)
                                }
                            }
                        }
                    }
                }
                .navigationBarBackButtonHidden(true)
                .onAppear {
                    if !didInitialize {
                        didInitialize = true
                        
                        // Setup physical controllers
                        setupPhysicalController()
                        
                        loadAllButtonLayouts()
                        importedPNGDataLandscape = loadPNG(key: "importedPNGLandscape")
                        importedPNGDataPortrait = loadPNG(key: "importedPNGPortrait")
                    }
                }
                .onDisappear {
                    stopListeningForPhysicalControllers()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    webViewModel.webView.evaluateJavaScript("if (window.pauseEmulator) { window.pauseEmulator(); }")
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    webViewModel.webView.evaluateJavaScript("if (window.resumeEmulator) { window.resumeEmulator(); }")
                }
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if isEditingLayout {
                            Button {
                                isEditingLayout = false
                                saveCurrentOrientationLayout()
                            } label: {
                                Text("Done")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Menu {
                            Menu("Settings") {
                                Toggle(isOn: $isAutoSprintEnabled) {
                                    Label("Auto Sprint", systemImage: "hare.fill")
                                }
                                .onChange(of: isAutoSprintEnabled) { enabled in
                                    handleAutoSprintToggle(enabled: enabled)
                                }
                                
                                Toggle(isOn: $isHapticFeedbackEnabled) {
                                    Label("Haptic Feedback", systemImage: "waveform.path.ecg")
                                }
                            }
                            
                            Menu("Layout") {
                                Button {
                                    isEditingLayout.toggle()
                                    if !isEditingLayout { saveCurrentOrientationLayout() }
                                } label: {
                                    Label("Customize Layout", systemImage: "rectangle.and.pencil.and.ellipsis")
                                }
                                Button(role: .destructive) {
                                    showResetLayoutConfirmation = true
                                } label: {
                                    Label("Reset Layout (Current)", systemImage: "arrow.clockwise")
                                }
                                // New reset all keymap button
                                Button(role: .destructive) {
                                    showResetKeymapConfirmation = true
                                } label: {
                                    Label("Reset All Keymap", systemImage: "keyboard")
                                }
                            }
                            
                            Menu("Skins") {
                                Button {
                                    showingPhotoPickerLandscape = true
                                } label: {
                                    Label("Import Skin (Landscape)", systemImage: "iphone.gen3.landscape")
                                }
                                Button {
                                    showingPhotoPickerPortrait = true
                                } label: {
                                    Label("Import Skin (Portrait)", systemImage: "iphone.gen3")
                                }
                                Toggle(isOn: $isSkinVisible) {
                                    Label("Show Skins", systemImage: "photo")
                                }
                                Button(role: .destructive) {
                                    showResetSkinsConfirmation = true
                                } label: {
                                    Label("Reset Skins to Defaults", systemImage: "arrow.clockwise")
                                }
                            }
                            
                            Menu("Help") {
                                Button {
                                    isHelpDialogPresented = true
                                } label: {
                                    Label("Help my screen turned white!", systemImage: "questionmark.circle")
                                }
                                Text("App Version: v\(appVersion)")
                            }
                            
                            Menu("Other") {
                                Button {
                                    isCreditsPresented.toggle()
                                } label: {
                                    Label("Credits", systemImage: "info.circle")
                                }
                            }
                            
                            Section {
                                Button(role: .destructive) {
                                    showForceReloadConfirmation = true
                                } label: {
                                    Label("Force Reload", systemImage: "arrow.clockwise.circle")
                                }
                                Button(role: .destructive) {
                                    showQuitConfirmation = true
                                } label: {
                                    Label("Quit", systemImage: "xmark.circle")
                                }
                            }
                        } label: {
                            Label("Menu", systemImage: "ellipsis.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                        }
                    }
                }
                // Confirmation for resetting layout
                .alert("Reset Layout", isPresented: $showResetLayoutConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        resetToDefaultLayoutCurrent()
                        saveCurrentOrientationLayout()
                    }
                } message: {
                    Text("Are you sure you want to reset the current layout to default?")
                }
                // Confirmation for resetting skins
                .alert("Reset Skins", isPresented: $showResetSkinsConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        resetSkinsToDefaults()
                    }
                } message: {
                    Text("Are you sure you want to reset all skins to default?")
                }
                // Confirmation for force reload
                .alert("Force Reload", isPresented: $showForceReloadConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reload", role: .destructive) {
                        forceReloadWebView()
                    }
                } message: {
                    Text("Are you sure you want to force reload the emulator? This may interrupt your current game.")
                }
                // Confirmation for resetting all keymaps
                .alert("Reset All Keymap", isPresented: $showResetKeymapConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        resetAllKeymap()
                    }
                } message: {
                    Text("Are you sure you want to reset all key mappings to their default values?")
                }
                .alert(isPresented: $isHelpDialogPresented) {
                    Alert(
                        title: Text("Help my screen turned white!"),
                        message: Text("If your screen has turned white and emulation is not working, try hitting the force reload button. If that does not work, try restarting the app. This usually resolves the issue."),
                        dismissButton: .default(Text("OK"))
                    )
                }
                .sheet(isPresented: $isCreditsPresented) {
                    CreditsView()
                }
                .confirmationDialog("Are you sure you want to quit?", isPresented: $showQuitConfirmation, titleVisibility: .visible) {
                    Button("Quit", role: .destructive) {
                        appDelegate?.stopServer()
                        quitGame()
                    }
                    Button("Cancel", role: .cancel) {}
                }
                // AirPlay
                .sheet(isPresented: $showAirPlaySheet) {
                    AirPlaySheetView()
                }
                // Photo pickers for skins
                .photosPicker(isPresented: $showingPhotoPickerLandscape, selection: $selectedPhotoLandscape, matching: .images, photoLibrary: .shared())
                .onChange(of: selectedPhotoLandscape) { newItem in
                    Task { await loadImageData(from: newItem, isLandscape: true) }
                }
                .photosPicker(isPresented: $showingPhotoPickerPortrait, selection: $selectedPhotoPortrait, matching: .images, photoLibrary: .shared())
                .onChange(of: selectedPhotoPortrait) { newItem in
                    Task { await loadImageData(from: newItem, isLandscape: false) }
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .navigationBarBackButtonHidden(true)
        }
        .id(reloadID)
        // Remap Key Sheet: uses friendly key strings instead of raw numeric codes
        .sheet(isPresented: Binding<Bool>(
            get: { remappingButton != nil },
            set: { if !$0 { remappingButton = nil } }
        )) {
            RemapKeySheetView(
                newKeyText: $newKeyText,
                buttonLabel: remappingButton?.label ?? "",
                onSave: {
                    guard let typedButton = remappingButton else { return }
                    // Convert typed key name into a numeric code
                    if let code = parseFriendlyKey(newKeyText) {
                        // Update the button's keyCode in both portrait & landscape arrays if found
                        if let idx = customButtonsPortrait.firstIndex(where: { $0.id == typedButton.id }) {
                            customButtonsPortrait[idx].keyCode = code
                        }
                        if let idx = customButtonsLandscape.firstIndex(where: { $0.id == typedButton.id }) {
                            customButtonsLandscape[idx].keyCode = code
                        }
                        saveAllButtonLayouts()
                    } else {
                        print("Invalid key name typed: \(newKeyText)")
                    }
                    remappingButton = nil
                    newKeyText = ""
                },
                onCancel: {
                    remappingButton = nil
                    newKeyText = ""
                }
            )
        }
    }
    
    // MARK: - Reset All Keymap
    private func resetAllKeymap() {
        // For each button in portrait and landscape, if we know its default code, restore it
        for i in 0..<customButtonsPortrait.count {
            if let defaultCode = defaultKeyMapping[customButtonsPortrait[i].label] {
                customButtonsPortrait[i].keyCode = defaultCode
            }
        }
        for i in 0..<customButtonsLandscape.count {
            if let defaultCode = defaultKeyMapping[customButtonsLandscape[i].label] {
                customButtonsLandscape[i].keyCode = defaultCode
            }
        }
        saveAllButtonLayouts()
    }
    
    // MARK: - Physical Controllers
    
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
                let webView = webViewModel.webView
                handleGamepadInput(gamepad, webView: webView)
            }
        }
    }
    
    private func handleGamepadInput(_ gamepad: GCExtendedGamepad, webView: WKWebView) {
        // Direction pad
        handleDirectionPad(gamepad.dpad, webView: webView)
        
        // A key
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
        
        // B key (skip if auto-sprint is on)
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
        checkDpad(dpad.up, 38, webView)    // Up
        checkDpad(dpad.down, 40, webView)  // Down
        checkDpad(dpad.left, 37, webView)  // Left
        checkDpad(dpad.right, 39, webView) // Right
        
        if isAutoSprintEnabled {
            // If left or right is pressed, hold B
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
    
    // MARK: - Skins
    
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
        } catch {
            print("Failed to load image data: \(error)")
        }
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
    
    // MARK: - Layout Persistence
    
    private func loadAllButtonLayouts() {
        if let loadedPortrait = loadButtonArray(key: "buttonLayoutPortrait") {
            customButtonsPortrait = loadedPortrait
        }
        if let loadedLandscape = loadButtonArray(key: "buttonLayoutLandscape") {
            customButtonsLandscape = loadedLandscape
        }
    }
    
    private func saveAllButtonLayouts() {
        saveButtonArray(customButtonsPortrait, key: "buttonLayoutPortrait")
        saveButtonArray(customButtonsLandscape, key: "buttonLayoutLandscape")
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
                CustomButton(label: "Up", keyCode: 38, x: UIScreen.main.bounds.width * 0.22, y: UIScreen.main.bounds.height * 0.12, width: 60, height: 60),
                CustomButton(label: "Down", keyCode: 40, x: UIScreen.main.bounds.width * 0.22, y: UIScreen.main.bounds.height * 0.25, width: 60, height: 60),
                CustomButton(label: "Left", keyCode: 37, x: UIScreen.main.bounds.width * 0.05, y: UIScreen.main.bounds.height * 0.185, width: 60, height: 60),
                CustomButton(label: "Right", keyCode: 39, x: UIScreen.main.bounds.width * 0.39, y: UIScreen.main.bounds.height * 0.185, width: 60, height: 60),
                CustomButton(label: "A", keyCode: 65, x: UIScreen.main.bounds.width * 0.82, y: UIScreen.main.bounds.height * 0.189, width: 60, height: 60),
                CustomButton(label: "B", keyCode: 66, x: UIScreen.main.bounds.width * 0.63, y: UIScreen.main.bounds.height * 0.189, width: 60, height: 60),
                CustomButton(label: "Start", keyCode: 32, x: UIScreen.main.bounds.width * 0.60, y: UIScreen.main.bounds.height * 0.32, width: 60, height: 60),
                CustomButton(label: "Select", keyCode: 83, x: UIScreen.main.bounds.width * 0.40, y: UIScreen.main.bounds.height * 0.32, width: 60, height: 60),
                CustomButton(label: "Reset", keyCode: 82, x: UIScreen.main.bounds.width * 0.05, y: UIScreen.main.bounds.height * 0.32, width: 60, height: 60)
            ]
        } else {
            let landscapeWidth = max(size.width, size.height)
            let landscapeHeight = min(size.width, size.height)
            customButtonsLandscape = [
                CustomButton(label: "Up", keyCode: 38, x: landscapeWidth * 0.13, y: landscapeHeight * 0.61, width: 60, height: 60),
                CustomButton(label: "Down", keyCode: 40, x: landscapeWidth * 0.13, y: landscapeHeight * 0.88, width: 60, height: 60),
                CustomButton(label: "Left", keyCode: 37, x: landscapeWidth * 0.06, y: landscapeHeight * 0.74, width: 60, height: 60),
                CustomButton(label: "Right", keyCode: 39, x: landscapeWidth * 0.20, y: landscapeHeight * 0.74, width: 60, height: 60),
                CustomButton(label: "A", keyCode: 65, x: landscapeWidth * 0.92, y: landscapeHeight * 0.67, width: 60, height: 60),
                CustomButton(label: "B", keyCode: 66, x: landscapeWidth * 0.84, y: landscapeHeight * 0.84, width: 60, height: 60),
                CustomButton(label: "Select", keyCode: 83, x: landscapeWidth * 0.44, y: landscapeHeight * 0.90, width: 60, height: 60),
                CustomButton(label: "Start", keyCode: 32, x: landscapeWidth * 0.56, y: landscapeHeight * 0.90, width: 60, height: 60),
                CustomButton(label: "Reset", keyCode: 82, x: landscapeWidth * 0.50, y: landscapeHeight * 0.04, width: 60, height: 60)
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
    
    // MARK: - WebView Reload & Recovery
    
    private func forceReloadWebView() {
        webViewRecoveryAttempts = 0
        webViewModel.webView.stopLoading()
        
        if let websiteDataTypes = NSSet(array: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]) as? Set<String> {
            WKWebsiteDataStore.default().removeData(ofTypes: websiteDataTypes, modifiedSince: Date(timeIntervalSince1970: 0), completionHandler: {})
        }
        
        appDelegate?.restartServer()
        startRecoveryCheck()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let url = URL(string: "http://127.0.0.1:8080/index.html?rom=\(game)") {
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
                webViewModel.webView.load(request)
            }
        }
        reloadID = UUID()
    }
    
    private func startRecoveryCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + recoveryTimeout) {
            checkWebViewRecovery()
        }
    }
    
    private func checkWebViewRecovery() {
        webViewModel.webView.evaluateJavaScript("document.body.innerHTML.length") { (result, error) in
            if let length = result as? Int {
                if length < 100 {
                    handleFailedRecovery()
                }
            } else {
                handleFailedRecovery()
            }
        }
    }
    
    private func handleFailedRecovery() {
        webViewRecoveryAttempts += 1
        if webViewRecoveryAttempts < maxRecoveryAttempts {
            forceReloadWebView()
        } else {
            webViewRecoveryAttempts = 0
            let alertController = UIAlertController(title: "Recovery Failed", message: "The emulator couldn't recover from a white screen error. Please try restarting the app.", preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default))
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let viewController = windowScene.windows.first?.rootViewController {
                viewController.present(alertController, animated: true)
            }
        }
    }
    
    // MARK: - On-Screen Button Presses
    
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
    
    // MARK: - Key Simulation
    
    private func sendKeyPress(keyCode: Int, webView: WKWebView, shouldProvideHaptic: Bool) {
        if shouldProvideHaptic && isHapticFeedbackEnabled {
            let f = UIImpactFeedbackGenerator(style: .rigid)
            f.prepare()
            f.impactOccurred()
        }
        
        let (codeString, keyString) = eventProperties(for: keyCode)
        let js = """
        (function() {
            var e = new KeyboardEvent('keydown', {
                bubbles: true,
                cancelable: true,
                code: '\(codeString)',
                key: '\(keyString)',
                keyCode: \(keyCode),
                which: \(keyCode)
            });
            document.dispatchEvent(e);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    private func sendKeyUp(keyCode: Int, webView: WKWebView, shouldProvideHaptic: Bool) {
        if shouldProvideHaptic && isHapticFeedbackEnabled {
            let f = UIImpactFeedbackGenerator(style: .rigid)
            f.prepare()
            f.impactOccurred()
        }
        
        let (codeString, keyString) = eventProperties(for: keyCode)
        let js = """
        (function() {
            var e = new KeyboardEvent('keyup', {
                bubbles: true,
                cancelable: true,
                code: '\(codeString)',
                key: '\(keyString)',
                keyCode: \(keyCode),
                which: \(keyCode)
            });
            document.dispatchEvent(e);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
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
    
    // MARK: - Auto Sprint
    
    private func handleAutoSprintToggle(enabled: Bool) {
        let w = webViewModel.webView
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
    
    // MARK: - Quit
    
    private func quitGame() {
        dismiss()
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
                        Link(destination: URL(string: "https://github.com/vapor/vapor")!) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Vapor").font(.body)
                                    Text("MIT License").font(.caption).foregroundColor(.secondary)
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
                        Link(destination: URL(string: "https://github.com/weichsel/ZIPFoundation")!) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("ZIP Foundation").font(.body)
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

// MARK: - NESWebView and WebViewModel

struct NESWebView: UIViewRepresentable {
    let game: String
    @ObservedObject var webViewModel: WebViewModel
    
    private var appDelegate: AppDelegate? {
        UIApplication.shared.delegate as? AppDelegate
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let w = webViewModel.webView
        if w.url == nil {
            loadGame(webView: w)
        }
        return w
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let currentURL = uiView.url?.absoluteString,
           !currentURL.contains("rom=\(game)") {
            restartServerAndLoadGame(webView: uiView)
        }
    }
    
    private func loadGame(webView: WKWebView) {
        if let url = URL(string: "http://127.0.0.1:8080/index.html?rom=\(game)") {
            webView.load(URLRequest(url: url))
        }
    }
    
    private func restartServerAndLoadGame(webView: WKWebView) {
        webView.stopLoading()
        appDelegate?.restartServer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadGame(webView: webView)
        }
    }
}

class WebViewModel: ObservableObject {
    @Published var webView: WKWebView = WKWebView()
}

// MARK: - CustomButton and DraggableButtonAreaView

struct CustomButton: Identifiable, Codable {
    let id: UUID
    let label: String
    var keyCode: Int
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
                // Semi-transparent area + label
                Rectangle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: button.width, height: button.height)
                    .overlay(
                        Text(button.label)
                            .foregroundColor(.white)
                            .font(.footnote)
                            .padding(2)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                    )
                
                // Circle drag-handle at bottom-right
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
                                
                                // Ensure the new size doesn't push the button out of screen bounds
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
        // Position the entire ZStack at the stored x/y plus drag offset, clamped to screen
        .position(
            x: min(max(button.x + dragOffset.width, button.width / 2), screenSize.width - button.width / 2),
            y: min(max(button.y + dragOffset.height, button.height / 2), screenSize.height - button.height / 2)
        )
        .gesture(
            isEditing
            ? DragGesture()
                .onChanged { v in
                    dragOffset = v.translation
                }
                .onEnded { v in
                    // Snap final position to stored x/y
                    button.x = min(max(button.x + v.translation.width, button.width / 2), screenSize.width - button.width / 2)
                    button.y = min(max(button.y + v.translation.height, button.height / 2), screenSize.height - button.height / 2)
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

struct PNGOverlay: View {
    let pressHandler: (Int) -> Void
    let releaseHandler: (Int) -> Void
    let isEditing: Bool
    
    @Binding var buttons: [CustomButton]
    let importedPNGData: Data?
    let isPortrait: Bool
    let remapHandler: (CustomButton) -> Void
    
    @AppStorage("isSkinVisible") private var isSkinVisible = true
    
    var body: some View {
        GeometryReader { g in
            let s = g.size
            ZStack {
                // Show the background skin if toggled on
                if isSkinVisible {
                    if let data = importedPNGData, let img = UIImage(data: data) {
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
                                Text("No Skin Imported")
                                    .foregroundColor(.white)
                            }
                        } else {
                            if let defaultHorizontal = UIImage(named: "StikNES_Horizontal") {
                                Image(uiImage: defaultHorizontal)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: s.width, height: s.height)
                            } else {
                                Rectangle().fill(Color.gray.opacity(0.5))
                                Text("No Skin Imported")
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                
                // Draggable / pressable buttons
                ForEach(buttons.indices, id: \.self) { index in
                    DraggableButtonAreaView(
                        button: $buttons[index],
                        isEditing: isEditing,
                        screenSize: s,
                        pressHandler: pressHandler,
                        releaseHandler: releaseHandler
                    )
                    .contextMenu {
                        // Only show "Remap Key" if editing
                        if isEditing {
                            Button("Remap Key") {
                                remapHandler(buttons[index])
                            }
                        }
                    }
                }
            }
        }
    }
}
