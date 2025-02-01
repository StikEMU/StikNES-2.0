//
//  AppDelegate.swift
//  StikNES
//
//  Created by Stephen on 12/30/24.
//

import UIKit
import Vapor

class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var app: Application?
    var emulatorDirectory: URL?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        setupEmulatorFiles()
        setupServer()
        return true
    }

    func setupEmulatorFiles() {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let emulatorPath = tempDirectory.appendingPathComponent("Emulator")

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: emulatorPath.path) {
            do {
                try fileManager.createDirectory(at: emulatorPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create emulator directory: \(error)")
                return
            }
        }

        let emulatorFiles = ["index.html", "nes_rust_wasm.js", "nes_rust_wasm_bg.wasm"]

        for fileName in emulatorFiles {
            guard let bundleURL = Bundle.main.url(forResource: fileName, withExtension: nil) else {
                print("Failed to find \(fileName) in bundle")
                continue
            }

            let destinationURL = emulatorPath.appendingPathComponent(fileName)
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
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

        do {
            var env = try Environment.detect()
            try LoggingSystem.bootstrap(from: &env)

            app = Application(env)
            guard let app = app else { return }

            app.middleware.use(IPRestrictionMiddleware())

            app.middleware.use(FileMiddleware(publicDirectory: emulatorDirectory.path))

            app.get { req in
                let indexPath = emulatorDirectory.appendingPathComponent("index.html").path
                do {
                    let html = try String(contentsOfFile: indexPath)
                    return Response(status: .ok, headers: ["Content-Type": "text/html"], body: .init(string: html))
                } catch {
                    return Response(status: .internalServerError)
                }
            }

            app.get("/*") { req -> Response in
                let filePath = emulatorDirectory.appendingPathComponent(req.url.path).path
                if FileManager.default.fileExists(atPath: filePath) {
                    return req.fileio.streamFile(at: filePath)
                } else {
                    return Response(status: .notFound, body: .init(string: "File not found"))
                }
            }

            DispatchQueue.global(qos: .background).async {
                do {
                    try app.run()
                } catch {
                    print("Failed to start server: \(error)")
                }
            }

            print("Server started at http://127.0.0.1:8080")
        } catch {
            print("Failed to setup Vapor server: \(error)")
        }
    }

    func restartServer() {
        app?.shutdown()
        print("Server stopped. Restarting...")

        if let emulatorDirectory = emulatorDirectory {
            let indexFileURL = emulatorDirectory.appendingPathComponent("index.html")
            do {
                if FileManager.default.fileExists(atPath: indexFileURL.path) {
                    try FileManager.default.removeItem(at: indexFileURL)
                }
                if let bundleURL = Bundle.main.url(forResource: "index", withExtension: "html") {
                    try FileManager.default.copyItem(at: bundleURL, to: indexFileURL)
                    print("index.html re-copied from the app bundle.")
                }
            } catch {
                print("Error reloading index.html: \(error)")
            }
        }

        setupServer()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        app?.shutdown()
        print("Server stopped.")
    }
}

struct IPRestrictionMiddleware: Middleware {
    func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        if request.remoteAddress?.ipAddress != "127.0.0.1" {
            let rejectionMessage = """
            -------------------------------------------------------------------
            Access Denied!
            -------------------------------------------------------------------
            Hey there, sneaky!
            This server is a private party, and you're not on the guest list.
            -------------------------------------------------------------------
            It's probably just a skill issue.
            -------------------------------------------------------------------
            """
            print("Rejected connection from: \(request.remoteAddress?.ipAddress ?? "Unknown Address")")
            return request.eventLoop.makeSucceededFuture(
                Response(status: .forbidden, body: .init(string: rejectionMessage))
            )
        }
        return next.respond(to: request)
    }
}
