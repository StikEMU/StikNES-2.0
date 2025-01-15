//
//  AppDelegate.swift
//  StikNES
//
//  Created by Stephen on 12/30/24.
//

import UIKit
import Swifter

class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var server: HttpServer?
    var emulatorDirectory: URL? // Define the emulator directory property

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        setupEmulatorFiles()
        setupServer()
        return true
    }

    func setupEmulatorFiles() {
        // Get the temporary directory
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let emulatorPath = tempDirectory.appendingPathComponent("Emulator")

        // Create the emulator directory if it doesn't exist
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: emulatorPath.path) {
            do {
                try fileManager.createDirectory(at: emulatorPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create emulator directory: \(error)")
                return
            }
        }

        // Define the filenames of the emulator files
        let emulatorFiles = [
            "index.html",
            "nes_rust_wasm.js",
            "nes_rust_wasm_bg.wasm"
        ]

        // Copy each file from the bundle to the temporary directory
        for fileName in emulatorFiles {
            guard let bundleURL = Bundle.main.url(forResource: fileName, withExtension: nil) else {
                print("Failed to find \(fileName) in bundle")
                continue
            }

            let destinationURL = emulatorPath.appendingPathComponent(fileName)
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL) // Remove existing files
                }
                try fileManager.copyItem(at: bundleURL, to: destinationURL)
            } catch {
                print("Failed to copy \(fileName): \(error)")
            }
        }

        self.emulatorDirectory = emulatorPath
        print("Emulator files copied to \(emulatorPath.path)")
    }

    func setupServer() {
        guard let emulatorDirectory = emulatorDirectory else {
            print("Emulator directory not set up")
            return
        }

        server = HttpServer()

        if let server = server {
            // Middleware to allow only localhost connections
            server.middleware.append { request in
                // Check if the request's address is localhost
                if request.address != "127.0.0.1" {
                    let rejectionMessage = """
                    -------------------------------------------------------------------
                    Access Denied!
                    -------------------------------------------------------------------
                    Hey there, sneaky!
                    This server is a private party, and your are not on the guest list.
                    -------------------------------------------------------------------
                    It's probably just a skill issue.
                    -------------------------------------------------------------------

                    """
                    print("Rejected connection from: \(request.address ?? "Unknown Address")")
                    return HttpResponse.raw(403, "Forbidden", ["Content-Type": "text/plain"], { writer in
                        try writer.write(rejectionMessage.data(using: .utf8) ?? Data())
                    })
                }
                return nil // Allow the request to proceed
            }

            // Serve index.html at the root
            server["/"] = { _ in
                let indexPath = emulatorDirectory.appendingPathComponent("index.html").path
                do {
                    let html = try String(contentsOfFile: indexPath)
                    return HttpResponse.ok(.html(html))
                } catch {
                    return HttpResponse.internalServerError
                }
            }

            // Serve all other files
            server["/:path"] = shareFilesFromDirectory(emulatorDirectory.path)

            // Start the server on localhost (127.0.0.1)
            do {
                try server.start(8080, forceIPv4: true)
                print("Server started at http://127.0.0.1:8080")
            } catch {
                print("Failed to start server: \(error)")
            }
        }
    }

    func restartServer() {
        server?.stop()
        print("Server stopped. Restarting...")
        setupServer()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        server?.stop()
        print("Server stopped.")
    }
}
