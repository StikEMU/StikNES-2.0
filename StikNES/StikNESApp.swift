//
//  StikNESApp.swift
//  StikNES
//
//  Created by Stephen on 12/29/24.
//

import SwiftUI

@main
struct StikNESApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appStatusChecker = AppStatusChecker()

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if appStatusChecker.isLoading {
                    LoadingView()
                } else if appStatusChecker.isAppAvailable {
                    ContentView()
                        .transition(.opacity)
                        .preferredColorScheme(.dark)
                } else {
                    ErrorView(errorMessage: appStatusChecker.errorMessage) {
                        appStatusChecker.checkAppStatus()
                    }
                }
            }
            .animation(.easeInOut, value: appStatusChecker.isLoading)
            .onAppear {
                appStatusChecker.checkAppStatus()
            }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Loading View
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            Text("Checking status...")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding()
    }
}

// MARK: - Error View
struct ErrorView: View {
    let errorMessage: String?
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.yellow)
            
            Text("Unable to Connect")
                .font(.title2)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text(errorMessage ?? "An internet connection is required to check the app status.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: retryAction) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: 200)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
        }
        .padding()
        .transition(.opacity)
    }
}

// MARK: - App Status Checker
class AppStatusChecker: ObservableObject {
    @Published var isAppAvailable: Bool = false
    @Published var isLoading: Bool = true
    @Published var errorMessage: String?

    private let url = URL(string: "https://stiknes.com/status.json")!

    func checkAppStatus() {
        isLoading = true
        errorMessage = nil

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
            }

            if let error = error {
                DispatchQueue.main.async {
                    self.isAppAvailable = false
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self.isAppAvailable = false
                    self.errorMessage = "No data received. Please check your connection."
                }
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                let appStatus = json?["value"] as? Bool ?? false
                let errorMsg = json?["error"] as? String
                
                DispatchQueue.main.async {
                    self.isAppAvailable = appStatus
                    self.errorMessage = appStatus ? nil : errorMsg ?? "The app is currently unavailable."
                }
            } catch {
                DispatchQueue.main.async {
                    self.isAppAvailable = false
                    self.errorMessage = "Invalid response format. Please try again."
                }
            }
        }.resume()
    }
}
