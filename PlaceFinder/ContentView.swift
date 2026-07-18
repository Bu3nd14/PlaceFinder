//
//  ContentView.swift
//  PlaceFinder
//
//  Created by Roberto on 18.07.26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                ChatView()
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Impostazioni", systemImage: "gear")
            }
        }
    }
}

#Preview {
    ContentView()
}