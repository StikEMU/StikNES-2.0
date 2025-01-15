//
//  StikNESApp.swift
//  StikNES
//
//  Created by Stephen on 12/29/24.
//

import SwiftUI

@main
struct StikNESApp: App {
    // The SwiftUI lifecycle will still rely on AppDelegate for UIApplication-related events
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
