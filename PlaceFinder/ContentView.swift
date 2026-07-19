//
//  ContentView.swift
//  PlaceFinder
//
//  Created by Roberto on 18.07.26.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Int = 0
    @StateObject private var strings = AppStrings.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ChatView()
            }
            .tabItem {
                Label("Chat", systemImage: selectedTab == 0
                      ? "bubble.left.and.bubble.right.fill"
                      : "bubble.left.and.bubble.right")
            }
            .tag(0)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(strings.settingsTab, systemImage: selectedTab == 1
                      ? "gearshape.fill"
                      : "gearshape")
            }
            .tag(1)
        }
        .tint(.blue)
        .onChange(of: selectedTab) { _, _ in
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }
}

#Preview {
    ContentView()
}