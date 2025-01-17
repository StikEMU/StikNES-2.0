//
//  SkinManagerView.swift
//  StikNES
//
//  Created by Stephen on 1/17/25.
//

import SwiftUI
import ZIPFoundation
import PDFKit

struct SkinManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var importedSkins: [SkinPreview] = []
    @State private var activeSkinIdentifier: String? = UserDefaults.standard.string(forKey: "activeSkinIdentifier")
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack {
                if importedSkins.isEmpty {
                    Text("No skins imported.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List(importedSkins, id: \.skin.identifier) { skinPreview in
                        HStack {
                            if let image = skinPreview.previewImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 80)
                                    .cornerRadius(8)
                                    .shadow(radius: 2)
                            } else {
                                Rectangle()
                                    .fill(Color.gray)
                                    .frame(width: 80, height: 80)
                                    .cornerRadius(8)
                                    .shadow(radius: 2)
                            }

                            VStack(alignment: .leading) {
                                Text(skinPreview.skin.name)
                                    .font(.headline)
                                Text("Identifier: \(skinPreview.skin.identifier)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if skinPreview.skin.identifier == activeSkinIdentifier {
                                Text("Active")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        .contentShape(Rectangle()) // Make the whole row tappable
                        .onTapGesture {
                            setActiveSkin(skinPreview.skin.identifier)
                        }
                    }
                }
            }
            .navigationBarTitle("Skin Manager", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import Skin") {
                        isImporting = true
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.init(filenameExtension: "deltaskin")!],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .onAppear {
                loadSkins()
            }
        }
    }

    // MARK: - Skin Management

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let fileURLs):
            guard let fileURL = fileURLs.first else {
                errorMessage = "No file selected."
                return
            }
            do {
                print("Attempting to import skin from: \(fileURL)")
                try importDeltaSkin(from: fileURL)
            } catch {
                errorMessage = "Failed to import skin: \(error.localizedDescription)"
                print("Error during import: \(error)")
            }
        case .failure(let error):
            errorMessage = "Failed to select file: \(error.localizedDescription)"
            print("File selection error: \(error)")
        }
    }

    private func importDeltaSkin(from fileURL: URL) throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        // Ensure temp directory exists
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        print("Temporary directory created at: \(tempDirectory)")

        // Extract .deltaskin file
        guard let archive = Archive(url: fileURL, accessMode: .read) else {
            throw NSError(domain: "SkinManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid .deltaskin file."])
        }
        print("Archive opened successfully.")

        for entry in archive {
            let destinationURL = tempDirectory.appendingPathComponent(entry.path)
            if entry.type == .file {
                try archive.extract(entry, to: destinationURL)
                print("Extracted file: \(destinationURL)")
            } else if entry.type == .directory {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                print("Created directory: \(destinationURL)")
            }
        }

        // Validate and parse info.json
        let infoFile = tempDirectory.appendingPathComponent("info.json")
        guard fileManager.fileExists(atPath: infoFile.path) else {
            throw NSError(domain: "SkinManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "info.json not found."])
        }
        print("info.json found at: \(infoFile)")

        do {
            let jsonData = try Data(contentsOf: infoFile)
            print("Raw JSON data: \(String(data: jsonData, encoding: .utf8) ?? "Unable to decode JSON data to String.")")

            let decoder = JSONDecoder()
            let skin = try decoder.decode(Skin.self, from: jsonData)
            print("Decoded skin: \(skin)")

            // Load the preview image from the first resizable PDF
            let previewPDFPath = skin.representations.iphone.standard?.portrait?.assets.resizable
            let previewImage = try loadPDFPreview(from: previewPDFPath, in: tempDirectory)

            // Save the preview image locally
            let savedImagePath = savePreviewImage(previewImage, for: skin.identifier)

            // Add the skin with its preview image to the list
            let skinPreview = SkinPreview(skin: skin, previewImage: previewImage, previewImagePath: savedImagePath)
            importedSkins.append(skinPreview)
            saveSkins()
            print("Successfully imported skin: \(skin.name)")
        } catch {
            print("Error decoding JSON: \(error)")
            throw NSError(domain: "SkinManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to decode info.json: \(error.localizedDescription)"])
        }

        // Clean up temp directory
        try fileManager.removeItem(at: tempDirectory)
        print("Temporary directory cleaned up.")
    }

    private func loadPDFPreview(from path: String?, in directory: URL) throws -> UIImage? {
        guard let path = path else {
            print("Preview PDF path not provided.")
            return nil
        }
        let pdfURL = directory.appendingPathComponent(path)
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            print("Failed to open PDF at \(pdfURL).")
            return nil
        }
        guard let pdfPage = pdfDocument.page(at: 0) else {
            print("No pages found in PDF at \(pdfURL).")
            return nil
        }

        let pageRect = pdfPage.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(pageRect)
            pdfPage.draw(with: .mediaBox, to: context.cgContext)
        }
        print("Successfully created preview image from PDF: \(pdfURL).")
        return image
    }

    private func savePreviewImage(_ image: UIImage?, for identifier: String) -> String? {
        guard let image = image,
              let data = image.pngData() else { return nil }

        let fileName = "\(identifier).png"
        let fileURL = getDocumentsDirectory().appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            print("Preview image saved at: \(fileURL)")
            return fileURL.path
        } catch {
            print("Failed to save preview image: \(error)")
            return nil
        }
    }

    private func loadPreviewImage(from path: String?) -> UIImage? {
        guard let path = path else { return nil }
        let fileURL = URL(fileURLWithPath: path)
        return UIImage(contentsOfFile: fileURL.path)
    }

    // MARK: - Persistence

    private func saveSkins() {
        let encoder = JSONEncoder()
        let previewsWithPaths = importedSkins.map { skinPreview -> SkinWithPath in
            return SkinWithPath(skin: skinPreview.skin, previewImagePath: skinPreview.previewImagePath)
        }

        if let data = try? encoder.encode(previewsWithPaths) {
            UserDefaults.standard.set(data, forKey: "importedSkins")
        }
    }

    private func loadSkins() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "importedSkins"),
           let previewsWithPaths = try? decoder.decode([SkinWithPath].self, from: data) {
            importedSkins = previewsWithPaths.map { skinWithPath in
                return SkinPreview(
                    skin: skinWithPath.skin,
                    previewImage: loadPreviewImage(from: skinWithPath.previewImagePath),
                    previewImagePath: skinWithPath.previewImagePath
                )
            }
        }
    }

    private func setActiveSkin(_ identifier: String) {
        activeSkinIdentifier = identifier
        UserDefaults.standard.set(identifier, forKey: "activeSkinIdentifier")
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - Models

struct Skin: Codable {
    let name: String
    let identifier: String
    let gameTypeIdentifier: String
    let debug: Bool
    let representations: Representations

    struct Representations: Codable {
        let iphone: DeviceRepresentations
    }

    struct DeviceRepresentations: Codable {
        let standard: OrientationRepresentations?
        let edgeToEdge: OrientationRepresentations?
    }

    struct OrientationRepresentations: Codable {
        let portrait: Layout?
        let landscape: Layout?
    }

    struct Layout: Codable {
        let assets: Assets
        let items: [Item]
        let mappingSize: Size
        let extendedEdges: Edges?

        struct Assets: Codable {
            let resizable: String
        }

        struct Item: Codable {
            let inputs: Inputs
            let frame: Frame
            let extendedEdges: Edges?

            struct Frame: Codable {
                let x: Double
                let y: Double
                let width: Double
                let height: Double
            }
        }

        struct Edges: Codable {
            let top: Double?
            let bottom: Double?
            let left: Double?
            let right: Double?
        }

        struct Size: Codable {
            let width: Double
            let height: Double
        }
    }

    enum Inputs: Codable {
        case dictionary([String: String])
        case array([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let dictionary = try? container.decode([String: String].self) {
                self = .dictionary(dictionary)
            } else if let array = try? container.decode([String].self) {
                self = .array(array)
            } else {
                throw DecodingError.typeMismatch(
                    Inputs.self,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected a dictionary or an array for `inputs`."
                    )
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .dictionary(let dictionary):
                try container.encode(dictionary)
            case .array(let array):
                try container.encode(array)
            }
        }
    }
}

struct SkinPreview: Identifiable {
    let id = UUID()
    let skin: Skin
    let previewImage: UIImage?
    var previewImagePath: String? = nil
}

struct SkinWithPath: Codable {
    let skin: Skin
    let previewImagePath: String?
}
