//
//  AppDelegate.swift
//  StikNES
//
//  Created by Stephen on 12/30/24.
//

import UIKit
import Vapor
import NIO
import Logging

class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var app: Application?
    private var emulatorDirectory: URL?
    private let logger = Logger(label: "com.emulator.server")
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    private enum ServerState {
        case notRunning
        case starting
        case running
        case stopping
    }
    private var currentServerState: ServerState = .notRunning
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        setupLogging()
        setupEmulatorFiles()
        restartServer()
        return true
    }
    
    private func setupLogging() {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .info
            return handler
        }
    }
    
    private func setupEmulatorFiles() {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let emulatorPath = tempDirectory.appendingPathComponent("Emulator")
        
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: emulatorPath,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            
            let emulatorFiles = ["index.html", "nes_rust_wasm.js", "nes_rust_wasm_bg.wasm", "ruffle.js", "1536bdedaf9e25772a09.wasm", "b4f51fad6e7438b66f8b.wasm", "core.ruffle.4f87b096b4318ab30d75.js", "core.ruffle.ece9872799c9441f1081.js"]
            
            for fileName in emulatorFiles {
                guard let bundleURL = Bundle.main.url(forResource: fileName, withExtension: nil) else {
                    logger.error("Failed to find \(fileName) in bundle")
                    continue
                }
                
                let destinationURL = emulatorPath.appendingPathComponent(fileName)
                try? fileManager.removeItem(at: destinationURL)
                try fileManager.copyItem(at: bundleURL, to: destinationURL)
            }
            
            self.emulatorDirectory = emulatorPath
            logger.info("Emulator files prepared at \(emulatorPath.path)")
        } catch {
            logger.error("Emulator file setup failed: \(error)")
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        logger.info("App entered background")
        beginBackgroundTask()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        logger.info("App will enter foreground")
        endBackgroundTask()
        if currentServerState == .notRunning {
            restartServer()
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        logger.info("App will terminate")
        stopServer()
        endBackgroundTask()
    }
    
    private func beginBackgroundTask() {
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                self?.logger.info("Background task expired")
                self?.stopServer()
                self?.endBackgroundTask()
            }
            logger.info("Background task started")
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
            logger.info("Background task ended")
        }
    }
    
    public func restartServer(force: Bool = false) {
        guard currentServerState == .notRunning || force else {
            logger.warning("Server restart blocked. Current state: \(currentServerState)")
            return
        }
        
        if currentServerState == .running {
            stopServer()
        }
        
        currentServerState = .starting
        
        setupEmulatorFiles()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            Thread.sleep(forTimeInterval: 0.5)
            
            self.startServer()
            
            self.verifyServerConnection()
        }
    }
    
    private func verifyServerConnection() {
        let url = URL(string: "http://127.0.0.1:8080")!
        let task = URLSession.shared.dataTask(with: url) { [weak self] (data, response, error) in
            if let error = error {
                self?.logger.error("Server restart verification failed: \(error.localizedDescription)")
                self?.currentServerState = .notRunning
                self?.restartServer() // Attempt restart on failure
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                self?.logger.warning("Server restart verification returned unexpected status")
                self?.currentServerState = .notRunning
                self?.restartServer() // Attempt restart on failure
                return
            }
            
            self?.logger.info("Server restart verified successfully")
            self?.currentServerState = .running
        }
        task.resume()
    }
    
    private func startServer() {
        guard let emulatorDirectory = emulatorDirectory, currentServerState != .running else {
            logger.warning("Server start prevented - already running or no directory")
            return
        }
        
        do {
            var env = try Environment.detect()
            env.arguments = ["vapor"]
            
            let app = Application(env)
            self.app = app
            
            app.http.server.configuration.hostname = "127.0.0.1"
            app.http.server.configuration.port = 8080
            app.http.server.configuration.responseCompression = .enabled
            app.http.server.configuration.requestDecompression = .enabled
            
            app.middleware.use(IPRestrictionMiddleware())
            app.middleware.use(FileMiddleware(publicDirectory: emulatorDirectory.path))
            
            // Serve the index page at the root
            app.get { req in
                let indexPath = emulatorDirectory.appendingPathComponent("index.html").path
                do {
                    let html = try String(contentsOfFile: indexPath)
                    return Response(status: .ok, headers: ["Content-Type": "text/html"], body: .init(string: html))
                } catch {
                    return Response(status: .internalServerError)
                }
            }
            
            // Serve any file requested under the emulator directory
            app.get("/*") { req -> Response in
                let filePath = emulatorDirectory.appendingPathComponent(req.url.path).path
                guard FileManager.default.fileExists(atPath: filePath) else {
                    return Response(status: .notFound, body: .init(string: "File not found"))
                }
                return req.fileio.streamFile(at: filePath)
            }
            
            // New route to select the emulator core based on file type
            app.get("play") { req -> Response in
                guard let fileName = req.query["file"] as String? else {
                    return Response(status: .badRequest, body: .init(string: "Missing 'file' query parameter"))
                }
                
                let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
                var htmlContent: String
                
                switch fileExtension {
                case "swf":
                    htmlContent = """
                    <!DOCTYPE html>
                    <html>
                    <head>
                      <meta charset="utf-8">
                      <title>Ruffle Emulator</title>
                      <script src="ruffle_core.js"></script>
                    </head>
                    <body>
                      <object data="\(fileName)" type="application/x-shockwave-flash">
                        Your browser does not support Flash.
                      </object>
                    </body>
                    </html>
                    """
                case "nes":
                    htmlContent = """
                    <!DOCTYPE html>
                    <html>
                    <head>
                      <meta charset="utf-8">
                      <title>NES Emulator</title>
                      <script src="nes_rust_wasm.js"></script>
                    </head>
                    <body>
                      <canvas id="nes-canvas"></canvas>
                    </body>
                    </html>
                    """
                default:
                    return Response(status: .badRequest, body: .init(string: "Unsupported file type"))
                }
                
                return Response(
                    status: .ok,
                    headers: ["Content-Type": "text/html"],
                    body: .init(string: htmlContent)
                )
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try app.run()
                    self.currentServerState = .running
                    self.logger.info("Server started successfully")
                } catch {
                    self.logger.error("Server startup failed: \(error)")
                    self.currentServerState = .notRunning
                }
            }
        } catch {
            logger.error("Vapor server setup failed: \(error)")
            currentServerState = .notRunning
        }
    }
    
    func stopServer() {
        guard currentServerState == .running else {
            logger.warning("Cannot stop server - not running")
            return
        }
        
        currentServerState = .stopping
        app?.shutdown()
        currentServerState = .notRunning
        logger.info("Server stopped")
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
