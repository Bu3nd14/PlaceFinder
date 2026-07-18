//
//  SettingsView.swift
//  PlaceFinder
//
//  Created on 18.07.26.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var service = OpenWebUIService.shared

    @State private var baseURL: String = ""
    @State private var userEmail: String = ""
    @State private var userPassword: String = ""
    @State private var googleAPIKey: String = ""
    @State private var isLoggingIn = false
    @State private var loginStatus: String?
    @State private var loginSuccess = false

    var body: some View {
        Form {
            Section(header: Text("Server")) {
                TextField("Base URL", text: $baseURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                TextField("Email", text: $userEmail)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                SecureField("Password", text: $userPassword)

                Button {
                    Task { await performLogin() }
                } label: {
                    HStack {
                        if isLoggingIn {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Login")
                    }
                }
                .disabled(isLoggingIn || baseURL.isEmpty || userEmail.isEmpty || userPassword.isEmpty)

                if let status = loginStatus {
                    Text(status)
                        .foregroundColor(loginSuccess ? .green : .red)
                        .font(.caption)
                }
            }

            Section(header: Text("Google Places API")) {
                SecureField("Google API Key", text: $googleAPIKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                Text("La chiave viene salvata localmente e usata per cercare luoghi nelle vicinanze.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Info")) {
                Text("PlaceFinder utilizza l'API Google Places per cercare luoghi vicino alla tua posizione e un LLM per fornire raccomandazioni personalizzate.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Impostazioni")
        .onAppear {
            loadSavedSettings()
        }
        .onDisappear {
            saveSettings()
        }
        .onChange(of: baseURL) { _ in saveSettings() }
        .onChange(of: userEmail) { _ in saveSettings() }
        .onChange(of: userPassword) { _ in saveSettings() }
        .onChange(of: googleAPIKey) { _ in saveSettings() }
    }

    private func loadSavedSettings() {
        baseURL = service.baseURL
        userEmail = service.userEmail
        userPassword = service.userPassword
        googleAPIKey = service.googleAPIKey
    }

    private func saveSettings() {
        service.baseURL = baseURL
        service.userEmail = userEmail
        service.userPassword = userPassword
        service.googleAPIKey = googleAPIKey
    }

    private func performLogin() async {
        isLoggingIn = true
        loginStatus = nil
        loginSuccess = false

        do {
            let token = try await service.loginToServer()
            loginStatus = "Login riuscito. Token: \(String(token.prefix(20)))..."
            loginSuccess = true
        } catch {
            loginStatus = error.localizedDescription
            loginSuccess = false
        }

        isLoggingIn = false
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}