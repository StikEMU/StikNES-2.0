//
//  ContentView.swift
//  StikNES
//
//  Created by Stephen on 12/29/24.
//

import SwiftUI

struct Game: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    var imageData: Data?

    init(id: UUID = UUID(), name: String, imageData: Data? = nil) {
        self.id = id
        self.name = name
        self.imageData = imageData
    }
}

struct ContentView: View {
    @State private var importedGames: [Game] = []
    @State private var showFileImporter = false
    @State private var selectedGame: Game?
    @State private var showImagePicker = false
    @State private var gamePendingImage: Game?

    private let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 20)
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if importedGames.isEmpty {
                    VStack(spacing: 8) {
                        Text("No games have been imported yet.")
                            .foregroundColor(.white)
                            .font(.title3)
                            .padding(.bottom, 8)
                        
                        Text("""
After you import and launch your first game, please open the menu, navigate to Layout, and select Customize Layout. This step is necessary to ensure the emulator functions properly.
""")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    VStack(spacing: 0) {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(importedGames) { game in
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
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        }
                        .scrollIndicators(.hidden)
                        Spacer()
                    }
                }

                if let selectedGame = selectedGame {
                    NavigationLink(
                        destination: EmulatorView(game: selectedGame.name)
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
                allowedContentTypes: [.init(filenameExtension: "nes")!],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .onAppear(perform: loadImportedGames)
            .navigationTitle("StikNES")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showFileImporter = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                            .shadow(radius: 2)
                    }
                    .accessibilityLabel("Import a new game")
                }
            }
        }
        .preferredColorScheme(.dark)
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showImagePicker) {
            ImagePicker { uiImage in
                guard let uiImage = uiImage else { return }
                guard var gameToUpdate = gamePendingImage else { return }

                if let data = uiImage.jpegData(compressionQuality: 0.8) {
                    if let index = importedGames.firstIndex(where: { $0.id == gameToUpdate.id }) {
                        importedGames[index].imageData = data
                        saveImportedGames()
                    }
                }
            }
        }
    }

    private func launchGame(_ game: Game) {
        selectedGame = game
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.restartServer()
        }
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        do {
            let selectedFiles = try result.get()
            guard let selectedFile = selectedFiles.first else { return }
            guard selectedFile.pathExtension.lowercased() == "nes" else { return }

            guard selectedFile.startAccessingSecurityScopedResource() else { return }
            defer { selectedFile.stopAccessingSecurityScopedResource() }

            let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let emulatorPath = tempDirectory.appendingPathComponent("Emulator")
            let destinationURL = emulatorPath.appendingPathComponent(selectedFile.lastPathComponent)

            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: emulatorPath.path) {
                try fileManager.createDirectory(at: emulatorPath, withIntermediateDirectories: true)
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: selectedFile, to: destinationURL)

            let game = Game(name: selectedFile.lastPathComponent)
            importedGames.append(game)
            saveImportedGames()
        } catch {
            print("Failed to import file: \(error)")
        }
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
                    .scaledToFit()
                    .frame(height: 80)
            } else {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
            }

            Text((game.name as NSString).deletingPathExtension)
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
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
