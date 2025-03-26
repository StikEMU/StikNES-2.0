//
//  ContentView.swift
//  StikNES
//
//  Created by Stephen on 12/29/24.
//

import SwiftUI
import ZIPFoundation
import Combine

struct Game: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    var imageData: Data?
    var developer: String?
    var releaseYear: String?
    var description: String?
    
    init(id: UUID = UUID(), name: String, imageData: Data? = nil, developer: String? = nil, releaseYear: String? = nil, description: String? = nil) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.developer = developer
        self.releaseYear = releaseYear
        self.description = description
    }
}

// Define sort options.
enum SortOrder: String, CaseIterable, Identifiable {
    case nameAscending = "Name Ascending"
    case nameDescending = "Name Descending"
    
    var id: String { self.rawValue }
}

struct ContentView: View {
    @AppStorage("username") private var username = "User"
    @AppStorage("customBackgroundColor") private var customBackgroundColorHex: String = Color.primaryBackground.toHex() ?? "#000000"
    @State private var selectedBackgroundColor: Color = Color(hex: UserDefaults.standard.string(forKey: "customBackgroundColor") ?? "#008080") ?? Color.primaryBackground
    @State private var importedGames: [Game] = []
    @State private var showFileImporter = false
    @State private var selectedGame: Game?
    @State private var showImagePicker = false
    @State private var gamePendingImage: Game?
    @State private var searchText = ""
    @State private var showSkinManager = false
    @State private var showSettings = false
    @State private var sortOrder: SortOrder = .nameAscending

    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]
    private let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Computed property that filters and sorts games.
    var sortedGames: [Game] {
        let games = importedGames.filter { game in
            searchText.isEmpty || game.name.localizedCaseInsensitiveContains(searchText)
        }
        switch sortOrder {
        case .nameAscending:
            return games.sorted { $0.name.lowercased() < $1.name.lowercased() }
        case .nameDescending:
            return games.sorted { $0.name.lowercased() > $1.name.lowercased() }
        }
    }
    
    // Group games by console type using the sorted list.
    var groupedGames: [String: [Game]] {
        Dictionary(grouping: sortedGames) { game in
            let lowercasedName = game.name.lowercased()
            if lowercasedName.hasSuffix(".nes") {
                return "NES"
            } else if lowercasedName.hasSuffix(".swf") {
                return "Flash"
            } else {
                return "Other"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                selectedBackgroundColor
                    .ignoresSafeArea()

                if importedGames.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "gamecontroller")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.blue.opacity(0.8))
                        
                        Text("No Games Imported")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        VStack(spacing: 8) {
                            Text("Tap the + button to import your games.")
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            
                            Text("""
After you import and launch your first game, please open the menu, navigate to Layout, and select Customize Layout. This step is necessary to ensure the emulator functions properly.
""")
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        Spacer()
                        Text("StikEMU v\(appVersion)")
                            .foregroundColor(.gray)
                            .font(.caption)
                            .padding(.bottom, 8)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(groupedGames.keys.sorted(), id: \.self) { consoleType in
                                // Section header for console type
                                Text(consoleType)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                
                                // Grid for games in each console type
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(groupedGames[consoleType] ?? []) { game in
                                        GameCardView(
                                            game: game,
                                            onLongPressSetPhoto: {
                                                gamePendingImage = game
                                                showImagePicker = true
                                            },
                                            onDelete: {
                                                deleteGame(game)
                                            }
                                        )
                                        .onTapGesture {
                                            launchGame(game)
                                        }
                                    }
                                }
                            }
                            // Footer with app version
                            Text("StikEMU v\(appVersion)")
                                .foregroundColor(.gray)
                                .font(.caption)
                                .padding(.bottom, 8)
                                .padding(.top, 16)
                        }
                    }
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                }
                
                if let selectedGame = selectedGame {
                    NavigationLink(
                        destination: GameDescriptionView(game: selectedGame, updateGame: updateGame)
                            .navigationBarTitleDisplayMode(.inline),
                        tag: selectedGame,
                        selection: $selectedGame
                    ) {
                        EmptyView()
                    }
                    .hidden()
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [
                    .init(filenameExtension: "nes")!,
                    .init(filenameExtension: "swf")!,
                    .init(filenameExtension: "zip")!
                ],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .onAppear(perform: loadImportedGames)
            .navigationTitle("Hello, \(username)!")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // Discord Button
                        Button {
                            if let url = URL(string: "https://discord.gg/a6qxs97Gun") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Discord", systemImage: "ellipsis.message.fill")
                        }
                        
                        // Source Code Button
                        Button {
                            if let url = URL(string: "https://github.com/StikEMU/StikNES-2.0") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        
                        // Privacy Policy Button
                        Button {
                            if let url = URL(string: "https://stiknes.com") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Privacy Policy", systemImage: "lock.doc")
                        }
                        
                        // Skin Manager Button
                        Button {
                            showSkinManager = true
                        } label: {
                            Label("Skin Manager", systemImage: "paintbrush.fill")
                        }
                        
                        Button {
                            showSettings  = true
                        } label: {
                            Label("App Settings", systemImage: "gearshape.fill")
                        }
                        
                        // Sort Menu
                        Menu {
                            Button("Name Ascending") {
                                sortOrder = .nameAscending
                            }
                            Button("Name Descending") {
                                sortOrder = .nameDescending
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                        
                        // Import Game Button
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Import Game", systemImage: "plus.circle.fill")
                        }
                    } label: {
                        Label("Menu", systemImage: "ellipsis.circle")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showSkinManager) {
                SkinManagerView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .onReceive(timer) { _ in
            refreshBackground()
        }
        .preferredColorScheme(.dark)
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showImagePicker) {
            ImagePicker { uiImage in
                guard let uiImage = uiImage, var gameToUpdate = gamePendingImage else { return }
                if let data = uiImage.jpegData(compressionQuality: 0.8) {
                    if let index = importedGames.firstIndex(where: { $0.id == gameToUpdate.id }) {
                        importedGames[index].imageData = data
                        saveImportedGames()
                    }
                }
            }
        }
    }
    
    private func refreshBackground() {
        selectedBackgroundColor = Color(hex: customBackgroundColorHex) ?? Color.primaryBackground
    }
    
    private func launchGame(_ game: Game) {
        selectedGame = game
    }
    
    private func updateGame(_ updatedGame: Game) {
        if let index = importedGames.firstIndex(where: { $0.id == updatedGame.id }) {
            importedGames[index] = updatedGame
            saveImportedGames()
        }
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        do {
            let selectedFiles = try result.get()
            guard let selectedFile = selectedFiles.first else { return }
            
            guard selectedFile.startAccessingSecurityScopedResource() else { return }
            defer { selectedFile.stopAccessingSecurityScopedResource() }
            
            let fileManager = FileManager.default
            let lowercasedExtension = selectedFile.pathExtension.lowercased()
            if lowercasedExtension == "zip" {
                let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                let unzipDirectory = tempDirectory.appendingPathComponent(UUID().uuidString)
                try fileManager.createDirectory(at: unzipDirectory, withIntermediateDirectories: true)
                
                try fileManager.unzipItem(at: selectedFile, to: unzipDirectory)
                
                let gameFiles = try fileManager.contentsOfDirectory(at: unzipDirectory, includingPropertiesForKeys: nil)
                    .filter { ["nes", "swf"].contains($0.pathExtension.lowercased()) }
                
                for gameFile in gameFiles {
                    try importGameFile(gameFile)
                }
            } else if lowercasedExtension == "nes" || lowercasedExtension == "swf" {
                try importGameFile(selectedFile)
            }
        } catch {
            print("Failed to import file: \(error)")
        }
    }
    
    private func importGameFile(_ fileURL: URL) throws {
        let fileManager = FileManager.default
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let emulatorPath = tempDirectory.appendingPathComponent("Emulator")
        
        if !fileManager.fileExists(atPath: emulatorPath.path) {
            try fileManager.createDirectory(at: emulatorPath, withIntermediateDirectories: true)
        }
        
        let destinationURL = emulatorPath.appendingPathComponent(fileURL.lastPathComponent)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: fileURL, to: destinationURL)
        
        let game = Game(name: fileURL.lastPathComponent)
        importedGames.append(game)
        saveImportedGames()
    }
    
    private func deleteGame(_ game: Game) {
        if let index = importedGames.firstIndex(where: { $0.id == game.id }) {
            importedGames.remove(at: index)
            saveImportedGames()
        }
    }
    
    private func saveImportedGames() {
        do {
            let data = try JSONEncoder().encode(importedGames)
            UserDefaults.standard.set(data, forKey: "importedGames")
        } catch {
            print("Failed to save imported games: \(error)")
        }
    }
    
    private func loadImportedGames() {
        guard let data = UserDefaults.standard.data(forKey: "importedGames") else { return }
        do {
            importedGames = try JSONDecoder().decode([Game].self, from: data)
        } catch {
            print("Failed to load imported games: \(error)")
        }
    }
}

struct GameCardView: View {
    let game: Game
    let onLongPressSetPhoto: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let imageData = game.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 120)
                    .clipped()
                    .cornerRadius(12)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 120)
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
            }
            Text((game.name as NSString).deletingPathExtension)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.2))
        )
        .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
        .contextMenu {
            Button {
                onLongPressSetPhoto()
            } label: {
                Label("Set Photo", systemImage: "photo")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Game", systemImage: "trash")
            }
        }
    }
}

struct GameDescriptionView: View {
    let game: Game
    let updateGame: (Game) -> Void
    @State private var showEditor = false
    
    var consoleType: String {
        let lowercasedName = game.name.lowercased()
        if lowercasedName.hasSuffix(".nes") {
            return "NES"
        } else if lowercasedName.hasSuffix(".swf") {
            return "Flash"
        }
        return "Unknown Console"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let imageData = game.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 200)
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                    }
                }
                
                Text((game.name as NSString).deletingPathExtension)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                HStack {
                    Text("Console: ")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text(consoleType)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                if let developer = game.developer, !developer.isEmpty {
                    HStack {
                        Text("Developer: ")
                            .foregroundColor(.gray)
                        Text(developer)
                            .foregroundColor(.white)
                    }
                }
                
                if let releaseYear = game.releaseYear, !releaseYear.isEmpty {
                    HStack {
                        Text("Release Year: ")
                            .foregroundColor(.gray)
                        Text(releaseYear)
                            .foregroundColor(.white)
                    }
                }
                
                if let description = game.description, !description.isEmpty {
                    Text(description)
                        .foregroundColor(.white)
                        .padding(.top, 8)
                }
                
                NavigationLink(destination: EmulatorView(game: game.name)) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Play")
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.vertical)
                }
                
                Spacer()
            }
            .padding()
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showEditor = true
                }) {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            GameInfoEditorView(game: game) { updatedGame in
                updateGame(updatedGame)
            }
        }
    }
}

struct GameInfoEditorView: View {
    @Environment(\.presentationMode) var presentationMode
    var game: Game
    var onSave: (Game) -> Void
    
    @State private var developer: String = ""
    @State private var releaseYear: String = ""
    @State private var descriptionText: String = ""
    
    init(game: Game, onSave: @escaping (Game) -> Void) {
        self.game = game
        self.onSave = onSave
        _developer = State(initialValue: game.developer ?? "")
        _releaseYear = State(initialValue: game.releaseYear ?? "")
        _descriptionText = State(initialValue: game.description ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Developer")) {
                    TextField("Developer", text: $developer)
                }
                Section(header: Text("Release Year")) {
                    TextField("Release Year", text: $releaseYear)
                }
                Section(header: Text("Description")) {
                    TextEditor(text: $descriptionText)
                        .frame(height: 150)
                }
            }
            .navigationBarTitle("Edit Info", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    var updatedGame = game
                    updatedGame.developer = developer
                    updatedGame.releaseYear = releaseYear
                    updatedGame.description = descriptionText
                    onSave(updatedGame)
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    var onImagePicked: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            parent.onImagePicked(image)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onImagePicked(nil)
            picker.dismiss(animated: true)
        }
    }
}
