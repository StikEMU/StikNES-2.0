//
//  NewSettingsView.swift
//  StikEMU
//
//  Created by Stephen on 3/25/25.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("username") private var username = "User"
    @AppStorage("customBackgroundColor") private var customBackgroundColorHex: String = Color.primaryBackground.toHex() ?? "#000000"
    @AppStorage("selectedAppIcon") private var selectedAppIcon: String = "AppIcon" // default app icon

    @State private var selectedBackgroundColor: Color = Color.primaryBackground
    @State private var showIconPopover = false
    
    private let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }()
    
    var body: some View {
        ZStack {
            // Apply the selected background color
            selectedBackgroundColor
                .ignoresSafeArea()

            Form {
                Section(header: Text("General").font(.headline).foregroundColor(.primaryText)) {
                    HStack {
                        Label("", systemImage: "person.fill")
                            .foregroundColor(.primaryText)
                        Spacer()
                        TextField("Username", text: $username)
                            .foregroundColor(.primaryText)
                            .padding(10)
                            .background(Color.cardBackground)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedBackgroundColor, lineWidth: 1)
                            )
                    }
                    .listRowBackground(Color.cardBackground)
                }

                Section(header: Text("Appearance").font(.headline).foregroundColor(.primaryText)) {
                    ColorPicker("Background Color", selection: $selectedBackgroundColor)
                        .onChange(of: selectedBackgroundColor) { newColor in
                            saveCustomBackgroundColor(newColor)
                        }
                        .listRowBackground(Color.cardBackground)
                        .foregroundColor(.primaryText)
                    
                    Button(action: {
                        showIconPopover.toggle()
                    }) {
                        HStack {
                            Text("App Icon")
                                .foregroundColor(.primaryText)
                            Spacer()
                            Text(selectedAppIcon == "AppIcon" ? "Default" : selectedAppIcon)
                                .foregroundColor(.primaryText)
                        }
                    }
                    .popover(isPresented: $showIconPopover) {
                        VStack(spacing: 15) {
                            Text("Select App Icon")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.top)
                                .shadow(radius: 1)

                            Divider()
                                .padding(.horizontal)

                            iconButton("Default", icon: "AppIcon")
                            iconButton("Peach", icon: "PeachIcon")
                            iconButton("Green", icon: "GreenIcon")

                            Spacer()

                            Button(action: {
                                showIconPopover = false
                            }) {
                                Text("Close")
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(.white.opacity(0.2))
                                    .cornerRadius(10)
                                    .padding(.horizontal)
                            }
                        }
                        .padding()
                        .background(selectedBackgroundColor)
                        .cornerRadius(20)
                        .shadow(radius: 5)
                    }
                    .listRowBackground(Color.cardBackground)
                }

                Section(header: Text("About").font(.headline).foregroundColor(.primaryText)) {
                    HStack {
                        Text("Version:")
                            .foregroundColor(.secondaryText)
                        Spacer()
                        Text("\(appVersion)")
                            .foregroundColor(.primaryText)
                    }
                    .listRowBackground(Color.cardBackground)
                    
                    HStack {
                        Text("Creator:")
                            .foregroundColor(.secondaryText)
                        Spacer()
                        Text("Stephen")
                            .foregroundColor(.primaryText)
                    }
                    .listRowBackground(Color.cardBackground)
                    
                    HStack {
                        Text("Collaborators:")
                            .foregroundColor(.secondaryText)
                        Spacer()
                        Text("Neo")
                            .foregroundColor(.primaryText)
                    }
                    .listRowBackground(Color.cardBackground)

                    HStack {
                        Text("Icon by:")
                            .foregroundColor(.secondaryText)
                        Spacer()
                        Text("Stephen")
                            .foregroundColor(.primaryText)
                    }
                    .listRowBackground(Color.cardBackground)
                    
                    Button(action: {
                        // Open the source code repository URL
                        if let url = URL(string: "https://github.com/orgs/StikTools/repositories") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Text("View Source Code")
                                .foregroundColor(.secondaryText)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.primaryText)
                        }
                    }
                    .listRowBackground(Color.cardBackground)
                }
            }
            .background(selectedBackgroundColor)
            .scrollContentBackground(.hidden)
            .navigationBarTitle("Settings")
            .font(.bodyFont)
            .accentColor(.accentColor)
        }
        .onAppear {
            loadCustomBackgroundColor()
        }
    }

    // Load custom background color from stored hex string
    private func loadCustomBackgroundColor() {
        selectedBackgroundColor = Color(hex: customBackgroundColorHex) ?? Color.primaryBackground
    }

    // Save custom background color as hex string
    private func saveCustomBackgroundColor(_ color: Color) {
        customBackgroundColorHex = color.toHex() ?? "#000000"
    }

    // Change the app icon
    private func changeAppIcon(to iconName: String) {
        selectedAppIcon = iconName
        UIApplication.shared.setAlternateIconName(iconName == "AppIcon" ? nil : iconName) { error in
            if let error = error {
                print("Error changing app icon: \(error.localizedDescription)")
            }
        }
    }

    // Helper function to create icon buttons
    private func iconButton(_ label: String, icon: String) -> some View {
        Button(action: {
            changeAppIcon(to: icon)
            showIconPopover = false
        }) {
            HStack {
                Image(uiImage: UIImage(named: icon) ?? UIImage())
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text(label)
                    .foregroundColor(.primaryText)
                Spacer()
            }
            .padding()
            .background(Color.white.opacity(0.2))
            .cornerRadius(10)
        }
        .padding(.horizontal)
    }
}

extension Color {
    func toHex() -> String? {
        let components = UIColor(self).cgColor.components
        let r = Float(components?[0] ?? 0)
        let g = Float(components?[1] ?? 0)
        let b = Float(components?[2] ?? 0)
        let hex = String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        return "#" + hex
    }
    
    init?(hex: String) {
        let r, g, b: CGFloat
        let start = hex.index(hex.startIndex, offsetBy: 1)
        let hexColor = String(hex[start...])

        if hexColor.count == 6, let hexNumber = Int(hexColor, radix: 16) {
            r = CGFloat((hexNumber & 0xff0000) >> 16) / 255
            g = CGFloat((hexNumber & 0x00ff00) >> 8) / 255
            b = CGFloat(hexNumber & 0x0000ff) / 255
            self.init(red: r, green: g, blue: b)
            return
        }

        return nil
    }
}

// Define a theme
extension Color {
    static let primaryBackground = Color.teal
    static let cardBackground = Color.white.opacity(0.2)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.7)
}
