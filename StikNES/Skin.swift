//
//  Skin.swift
//  StikNES
//
//  Created by Stephen on 1/28/25.
//

import SwiftUI
import Photos

struct Skin: Identifiable, Codable {
    let id: String
    let name: String
    let imageUrl: String
    let category: String
    let description: String
    let creator: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, imageUrl = "image_url", category, description, creator
    }
}

struct SkinResponse: Codable {
    let skins: [Skin]
}

struct SkinManagerView: View {
    @State private var skins: [Skin] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            ZStack {
                if isLoading {
                    ProgressView("Loading...")
                        .scaleEffect(1.5)
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 16) {
                        Text("Oops!")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            refreshData()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(skins) { skin in
                                SkinCardView(
                                    skin: skin,
                                    onDownloadAndSave: { downloadAndSaveSkin(skin) }
                                )
                                .padding(.horizontal)
                            }
                        }
                        .padding(.top, 20)
                    }
                }
            }
            .navigationTitle("Skins")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshData) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear(perform: refreshData)
        }
    }
    
    private func fetchSkins() {
        guard let url = URL(string: "https://stiknes.com/skins.json") else {
            errorMessage = "Invalid URL."
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }
                
                guard let data = data else {
                    errorMessage = "No data received."
                    return
                }
                
                do {
                    let decodedResponse = try JSONDecoder().decode(SkinResponse.self, from: data)
                    self.skins = decodedResponse.skins
                } catch {
                    errorMessage = "Failed to decode JSON: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func refreshData() {
        fetchSkins()
    }
    
    private func downloadAndSaveSkin(_ skin: Skin) {
        guard let url = URL(string: skin.imageUrl) else { return }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, let image = UIImage(data: data) else {
                print("Download failed: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            PHPhotoLibrary.requestAuthorization { status in
                guard status == .authorized else {
                    print("Permission to save to Photos was denied.")
                    return
                }
                
                PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    request.creationDate = Date()
                } completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            print("Skin saved to Photos successfully!")
                        } else {
                            print("Failed to save to Photos: \(error?.localizedDescription ?? "Unknown error")")
                        }
                    }
                }
            }
        }
        
        task.resume()
    }
}

struct SkinCardView: View {
    let skin: Skin
    let onDownloadAndSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AsyncImage(url: URL(string: skin.imageUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 100, height: 100)
                .cornerRadius(12)
                .shadow(radius: 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(skin.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("By \(skin.creator)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            Button(action: onDownloadAndSave) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save to Photos")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}
