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

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.activeTintColor = .blue
        view.tintColor = .gray
        return view
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

private let friendlyToCode: [String: Int] = [
    "backspace": 8,
    "tab": 9,
    "enter": 13,
    "return": 13,
    "shift": 16,
    "ctrl": 17,
    "control": 17,
    "alt": 18,
    "pause": 19,
    "capslock": 20,
    "escape": 27,
    "esc": 27,
    "space": 32,
    "pageup": 33,
    "pagedown": 34,
    "end": 35,
    "home": 36,
    "left": 37, "arrowleft": 37,
    "up": 38, "arrowup": 38,
    "right": 39, "arrowright": 39,
    "down": 40, "arrowdown": 40,
    "insert": 45,
    "delete": 46,
    "0": 48,
    "1": 49,
    "2": 50,
    "3": 51,
    "4": 52,
    "5": 53,
    "6": 54,
    "7": 55,
    "8": 56,
    "9": 57,
    "a": 65,
    "b": 66,
    "c": 67,
    "d": 68,
    "e": 69,
    "f": 70,
    "g": 71,
    "h": 72,
    "i": 73,
    "j": 74,
    "k": 75,
    "l": 76,
    "m": 77,
    "n": 78,
    "o": 79,
    "p": 80,
    "q": 81,
    "r": 82,
    "s": 83,
    "t": 84,
    "u": 85,
    "v": 86,
    "w": 87,
    "x": 88,
    "y": 89,
    "z": 90,
    "leftwindow": 91,
    "rightwindow": 92,
    "select": 93,
    "numpad0": 96,
    "numpad1": 97,
    "numpad2": 98,
    "numpad3": 99,
    "numpad4": 100,
    "numpad5": 101,
    "numpad6": 102,
    "numpad7": 103,
    "numpad8": 104,
    "numpad9": 105,
    "multiply": 106,
    "add": 107,
    "subtract": 109,
    "decimal": 110,
    "divide": 111,
    "f1": 112,
    "f2": 113,
    "f3": 114,
    "f4": 115,
    "f5": 116,
    "f6": 117,
    "f7": 118,
    "f8": 119,
    "f9": 120,
    "f10": 121,
    "f11": 122,
    "f12": 123,
    "numlock": 144,
    "scrolllock": 145,
    "semicolon": 186,
    "equals": 187,
    "equal": 187,
    "comma": 188,
    "dash": 189,
    "period": 190,
    "slash": 191,
    "grave": 192,
    "openbracket": 219,
    "backslash": 220,
    "closebracket": 221,
    "quote": 222
]

private let codeToFriendly: [Int: String] = [
    8: "Backspace",
    9: "Tab",
    13: "Enter",
    16: "Shift",
    17: "Ctrl",
    18: "Alt",
    19: "Pause",
    20: "CapsLock",
    27: "Escape",
    32: "Space",
    33: "PageUp",
    34: "PageDown",
    35: "End",
    36: "Home",
    37: "Left",
    38: "Up",
    39: "Right",
    40: "Down",
    45: "Insert",
    46: "Delete",
    48: "0",
    49: "1",
    50: "2",
    51: "3",
    52: "4",
    53: "5",
    54: "6",
    55: "7",
    56: "8",
    57: "9",
    65: "A",
    66: "B",
    67: "C",
    68: "D",
    69: "E",
    70: "F",
    71: "G",
    72: "H",
    73: "I",
    74: "J",
    75: "K",
    76: "L",
    77: "M",
    78: "N",
    79: "O",
    80: "P",
    81: "Q",
    82: "R",
    83: "S",
    84: "T",
    85: "U",
    86: "V",
    87: "W",
    88: "X",
    89: "Y",
    90: "Z",
    91: "LeftWindow",
    92: "RightWindow",
    93: "Select",
    96: "Numpad0",
    97: "Numpad1",
    98: "Numpad2",
    99: "Numpad3",
    100: "Numpad4",
    101: "Numpad5",
    102: "Numpad6",
    103: "Numpad7",
    104: "Numpad8",
    105: "Numpad9",
    106: "Multiply",
    107: "Add",
    109: "Subtract",
    110: "Decimal",
    111: "Divide",
    112: "F1",
    113: "F2",
    114: "F3",
    115: "F4",
    116: "F5",
    117: "F6",
    118: "F7",
    119: "F8",
    120: "F9",
    121: "F10",
    122: "F11",
    123: "F12",
    144: "NumLock",
    145: "ScrollLock",
    186: "Semicolon",
    187: "Equals",
    188: "Comma",
    189: "Dash",
    190: "Period",
    191: "Slash",
    192: "Grave",
    219: "OpenBracket",
    220: "Backslash",
    221: "CloseBracket",
    222: "Quote"
]

private let defaultKeyMapping: [String: Int] = [
    "Up": 38,
    "Down": 40,
    "Left": 37,
    "Right": 39,
    "A": 65,
    "B": 66,
    "C": 67,
    "X": 88,
    "Start": 32,
    "Select": 83,
    "Reset": 82,
    "Enter": 13
]

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
            .navigationBarItems(leading: Button("Cancel", action: onCancel), trailing: Button("Save", action: onSave))
        }
    }
}

struct CustomURLSheetView: View {
    @Binding var urlString: String
    var onSave: () -> Void
    var onCancel: () -> Void
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Enter Custom URL")) {
                    TextField("Custom URL", text: $urlString)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .navigationBarTitle("Custom URL", displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel", action: onCancel), trailing: Button("Save", action: onSave))
        }
    }
}

struct KeyBindings: Codable {
    var portrait: [CustomButton]
    var landscape: [CustomButton]
}

struct KeyBindingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var keyBindings: KeyBindings
    init(keyBindings: KeyBindings) {
        self.keyBindings = keyBindings
    }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        let decoder = JSONDecoder()
        self.keyBindings = try decoder.decode(KeyBindings.self, from: data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        let data = try encoder.encode(keyBindings)
        return .init(regularFileWithContents: data)
    }
}

struct EmulatorView: View {
    let game: String
    @StateObject private var webViewModel: WebViewModel
    @StateObject private var externalDisplayManager: ExternalDisplayManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isAutoSprintEnabled") private var isAutoSprintEnabled = false
    @AppStorage("isHapticFeedbackEnabled") private var isHapticFeedbackEnabled = false
    @AppStorage("isSkinVisible") private var isSkinVisible = true
    @AppStorage("isExperimentalEnabled") private var isExperimentalEnabled = false
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
    @State private var showResetKeymapConfirmation = false
    private let maxRecoveryAttempts = 3
    private let recoveryTimeout = 5.0
    @State private var showAirPlaySheet = false
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
    @State private var customButtonsLandscape: [CustomButton] = {
        let w = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let h = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        return [
            CustomButton(label: "Up", keyCode: 38, x: w * 0.13, y: h * 0.61, width: 60, height: 60),
            CustomButton(label: "Down", keyCode: 40, x: w * 0.13, y: h * 0.88, width: 60, height: 60),
            CustomButton(label: "Left", keyCode: 37, x: w * 0.06, y: h * 0.74, width: 60, height: 60),
            CustomButton(label: "Right", keyCode: 39, x: w * 0.20, y: h * 0.74, width: 60, height: 60),
            CustomButton(label: "A", keyCode: 65, x: w * 0.92, y: h * 0.67, width: 60, height: 60),
            CustomButton(label: "B", keyCode: 66, x: w * 0.84, y: h * 0.84, width: 60, height: 60),
            CustomButton(label: "Select", keyCode: 83, x: w * 0.44, y: h * 0.90, width: 60, height: 60),
            CustomButton(label: "Start", keyCode: 32, x: w * 0.56, y: h * 0.90, width: 60, height: 60),
            CustomButton(label: "Reset", keyCode: 82, x: w * 0.50, y: h * 0.04, width: 60, height: 60)
        ]
    }()
    @State private var importedPNGDataLandscape: Data? = nil
    @State private var importedPNGDataPortrait: Data? = nil
    @State private var activePresses = Set<Int>()
    @State private var reloadID = UUID()
    @State private var remappingButton: CustomButton? = nil
    @State private var newKeyText: String = ""
    @State private var showCustomURLSheet = false
    @State private var customURLInput: String = ""
    @State private var isShowingFileImporter = false
    @State private var isShowingFileExporter = false
    @State private var exportDocument: KeyBindingsDocument? = nil
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
                            PNGOverlay(pressHandler: { keyCode in onScreenPress(keyCode: keyCode) }, releaseHandler: { keyCode in onScreenRelease(keyCode: keyCode) }, isEditing: isEditingLayout, buttons: displayedButtons, importedPNGData: pngDataToUse, isPortrait: true, remapHandler: { button in
                                remappingButton = button
                                newKeyText = friendlyKeyName(for: button.keyCode)
                            })
                            .frame(width: geometry.size.width, height: geometry.size.height * 0.5)
                        }
                    }
                    else if externalDisplayManager.externalScreenConnected && !isPortrait {
                        ZStack {
                            Color.black
                            PNGOverlay(pressHandler: { keyCode in onScreenPress(keyCode: keyCode) }, releaseHandler: { keyCode in onScreenRelease(keyCode: keyCode) }, isEditing: isEditingLayout, buttons: displayedButtons, importedPNGData: pngDataToUse, isPortrait: false, remapHandler: { button in
                                remappingButton = button
                                newKeyText = friendlyKeyName(for: button.keyCode)
                            })
                            .edgesIgnoringSafeArea(.all)
                        }
                    }
                    else {
                        if isPortrait {
                            VStack(spacing: 0) {
                                NESWebView(game: game, webViewModel: webViewModel)
                                    .frame(width: geometry.size.width, height: geometry.size.height * 0.5)
                                PNGOverlay(pressHandler: { keyCode in onScreenPress(keyCode: keyCode) }, releaseHandler: { keyCode in onScreenRelease(keyCode: keyCode) }, isEditing: isEditingLayout, buttons: displayedButtons, importedPNGData: pngDataToUse, isPortrait: true, remapHandler: { button in
                                    remappingButton = button
                                    newKeyText = friendlyKeyName(for: button.keyCode)
                                })
                                .frame(width: geometry.size.width, height: geometry.size.height * 0.5)
                            }
                        } else {
                            ZStack {
                                NESWebView(game: game, webViewModel: webViewModel)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                PNGOverlay(pressHandler: { keyCode in onScreenPress(keyCode: keyCode) }, releaseHandler: { keyCode in onScreenRelease(keyCode: keyCode) }, isEditing: isEditingLayout, buttons: displayedButtons, importedPNGData: pngDataToUse, isPortrait: false, remapHandler: { button in
                                    remappingButton = button
                                    newKeyText = friendlyKeyName(for: button.keyCode)
                                })
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
                                Label("Auto Sprint (NES)", systemImage: "hare.fill")
                            }
                            .onChange(of: isAutoSprintEnabled) { enabled in
                                handleAutoSprintToggle(enabled: enabled)
                            }
                            Toggle(isOn: $isHapticFeedbackEnabled) {
                                Label("Haptic Feedback", systemImage: "waveform.path.ecg")
                            }
                            Toggle(isOn: $isExperimentalEnabled) {
                                HStack {
                                    Image(systemName: "flame.fill")
                                    Text(isExperimentalEnabled ? "Disable Experimental Settings" : "Enable Experimental Settings")
                                }
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
                            Button(role: .destructive) {
                                showResetKeymapConfirmation = true
                            } label: {
                                Label("Reset All Keymap", systemImage: "keyboard")
                            }
                            Button {
                                exportDocument = KeyBindingsDocument(keyBindings: KeyBindings(portrait: customButtonsPortrait, landscape: customButtonsLandscape))
                                isShowingFileExporter = true
                            } label: {
                                Label("Export Key Bindings", systemImage: "square.and.arrow.down")
                            }
                            Button {
                                isShowingFileImporter = true
                            } label: {
                                Label("Import Key Bindings", systemImage: "square.and.arrow.up")
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
                        if isExperimentalEnabled {
                            Menu("Experimental") {
                                Button {
                                    customURLInput = webViewModel.customURL
                                    showCustomURLSheet = true
                                } label: {
                                    Label("Load Custom URL", systemImage: "link")
                                }
                                Button(role: .destructive) {
                                    webViewModel.customURL = ""
                                    forceReloadWebView()
                                } label: {
                                    Label("Reset URL", systemImage: "arrow.uturn.backward")
                                }
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
            .alert("Reset Layout", isPresented: $showResetLayoutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetToDefaultLayoutCurrent()
                    saveCurrentOrientationLayout()
                }
            } message: {
                Text("Are you sure you want to reset the current layout to default?")
            }
            .alert("Reset Skins", isPresented: $showResetSkinsConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetSkinsToDefaults()
                }
            } message: {
                Text("Are you sure you want to reset all skins to default?")
            }
            .alert("Force Reload", isPresented: $showForceReloadConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reload", role: .destructive) {
                    forceReloadWebView()
                }
            } message: {
                Text("Are you sure you want to force reload the emulator? This may interrupt your current game.")
            }
            .alert("Reset All Keymap", isPresented: $showResetKeymapConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetAllKeymap()
                }
            } message: {
                Text("Are you sure you want to reset all key mappings to their default values?")
            }
            .alert(isPresented: $isHelpDialogPresented) {
                Alert(title: Text("Help my screen turned white!"), message: Text("If your screen has turned white and emulation is not working, try hitting the force reload button. If that does not work, try restarting the app. This usually resolves the issue."), dismissButton: .default(Text("OK")))
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
            .sheet(isPresented: $showAirPlaySheet) {
                AirPlaySheetView()
            }
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
        .id(reloadID)
        .sheet(isPresented: Binding<Bool>(
            get: { remappingButton != nil },
            set: { if !$0 { remappingButton = nil } }
        )) {
            RemapKeySheetView(newKeyText: $newKeyText, buttonLabel: remappingButton?.label ?? "", onSave: {
                guard let typedButton = remappingButton else { return }
                if let code = parseFriendlyKey(newKeyText) {
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
            }, onCancel: {
                remappingButton = nil
                newKeyText = ""
            })
        }
        .sheet(isPresented: $showCustomURLSheet) {
            CustomURLSheetView(urlString: $customURLInput, onSave: {
                webViewModel.customURL = customURLInput
                showCustomURLSheet = false
                forceReloadWebView()
            }, onCancel: {
                showCustomURLSheet = false
            })
        }
        .fileExporter(isPresented: $isShowingFileExporter, document: exportDocument ?? KeyBindingsDocument(keyBindings: KeyBindings(portrait: customButtonsPortrait, landscape: customButtonsLandscape)), contentType: .json) { result in
            switch result {
            case .success(let url):
                print("Exported key bindings to: \(url)")
            case .failure(let error):
                print("Export error: \(error)")
            }
        }
        .fileImporter(isPresented: $isShowingFileImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    let decoder = JSONDecoder()
                    let keyBindings = try decoder.decode(KeyBindings.self, from: data)
                    customButtonsPortrait = keyBindings.portrait
                    customButtonsLandscape = keyBindings.landscape
                    print("Imported key bindings from \(url)")
                } else {
                    print("Failed to access security scoped resource")
                }
            } catch {
                print("Import error: \(error)")
            }
        }
    }
    private func parseFriendlyKey(_ input: String) -> Int? {
        friendlyToCode[input.lowercased()]
    }

    private func friendlyKeyName(for code: Int) -> String {
        codeToFriendly[code] ?? "\(code)"
    }

    private func eventProperties(for keyCode: Int) -> (String, String) {
        let name = codeToFriendly[keyCode] ?? ""
        switch keyCode {
        case 37: return ("ArrowLeft", "ArrowLeft")
        case 38: return ("ArrowUp", "ArrowUp")
        case 39: return ("ArrowRight", "ArrowRight")
        case 40: return ("ArrowDown", "ArrowDown")
        case 13: return ("Enter", "Enter")
        case 32: return ("Space", " ")
        default: return ("Key\(name)", name.lowercased())
        }
    }
    private func resetAllKeymap() {
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
            let w = max(size.width, size.height)
            let h = min(size.width, size.height)
            customButtonsLandscape = [
                CustomButton(label: "Up", keyCode: 38, x: w * 0.13, y: h * 0.61, width: 60, height: 60),
                CustomButton(label: "Down", keyCode: 40, x: w * 0.13, y: h * 0.88, width: 60, height: 60),
                CustomButton(label: "Left", keyCode: 37, x: w * 0.06, y: h * 0.74, width: 60, height: 60),
                CustomButton(label: "Right", keyCode: 39, x: w * 0.20, y: h * 0.74, width: 60, height: 60),
                CustomButton(label: "A", keyCode: 65, x: w * 0.92, y: h * 0.67, width: 60, height: 60),
                CustomButton(label: "B", keyCode: 66, x: w * 0.84, y: h * 0.84, width: 60, height: 60),
                CustomButton(label: "Select", keyCode: 83, x: w * 0.44, y: h * 0.90, width: 60, height: 60),
                CustomButton(label: "Start", keyCode: 32, x: w * 0.56, y: h * 0.90, width: 60, height: 60),
                CustomButton(label: "Reset", keyCode: 82, x: w * 0.50, y: h * 0.04, width: 60, height: 60)
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
    private func forceReloadWebView() {
        webViewRecoveryAttempts = 0
        webViewModel.webView.stopLoading()
        if let types = NSSet(array: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]) as? Set<String> {
            WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0), completionHandler: {})
        }
        appDelegate?.restartServer()
        startRecoveryCheck()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let urlString = webViewModel.customURL.isEmpty ? "http://127.0.0.1:8080/index.html?rom=\(game)" : webViewModel.customURL
            if let url = URL(string: urlString) {
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
               let vc = windowScene.windows.first?.rootViewController {
                vc.present(alertController, animated: true)
            }
        }
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
    private func sendKeyPress(keyCode: Int, webView: WKWebView, shouldProvideHaptic: Bool) {
        if shouldProvideHaptic && isHapticFeedbackEnabled {
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred()
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
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred()
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
                        Link(destination: URL(string: "https://github.com/ruffle-rs/ruffle/")!) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Ruffle").font(.body)
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
        let urlString = !webViewModel.customURL.isEmpty ? webViewModel.customURL : "http://127.0.0.1:8080/index.html?rom=\(game)"
        if let url = URL(string: urlString) {
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
    @AppStorage("customURL") var customURL: String = ""
}

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
                .onChanged { v in
                    dragOffset = v.translation
                }
                .onEnded { v in
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
                ForEach(buttons.indices, id: \.self) { index in
                    DraggableButtonAreaView(button: $buttons[index], isEditing: isEditing, screenSize: s, pressHandler: pressHandler, releaseHandler: releaseHandler)
                        .contextMenu {
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
