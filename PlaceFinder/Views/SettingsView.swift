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
    @State private var isAuthenticated = false

    var body: some View {
        Form {
            // MARK: Server Section
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Server", systemImage: "server.rack")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                    Text("URL del server LiteLLM proxy")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                TextField("Base URL", text: $baseURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                TextField("Email", text: $userEmail)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                SecureField("Password", text: $userPassword)

                if isAuthenticated {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                        Text("Connesso")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.green)
                    }
                }

                Button {
                    Task { await performLogin() }
                } label: {
                    HStack {
                        if isLoggingIn {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        }
                        Text("Login")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [.blue, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundColor(.white)
                }
                .disabled(isLoggingIn || baseURL.isEmpty || userEmail.isEmpty || userPassword.isEmpty)
                .opacity(baseURL.isEmpty || userEmail.isEmpty || userPassword.isEmpty ? 0.5 : 1)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))

                if let status = loginStatus {
                    HStack(spacing: 6) {
                        Image(systemName: loginSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(loginSuccess ? .green : .red)
                        Text(status)
                            .font(.caption.weight(.medium))
                            .foregroundColor(loginSuccess ? .green : .red)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill((loginSuccess ? Color.green : Color.red).opacity(0.1))
                    )
                }
            }

            // MARK: Google Places Section
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Google Places API", systemImage: "map.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                    Text("Chiave per ricercare luoghi nelle vicinanze")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                SecureField("Google API Key", text: $googleAPIKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                Text("La chiave viene salvata localmente e usata per cercare luoghi nelle vicinanze.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // MARK: Info Section
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Informazioni", systemImage: "info.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                Text("PlaceFinder utilizza l'API Google Places per cercare luoghi vicino alla tua posizione e un LLM per fornire raccomandazioni personalizzate.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Impostazioni")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fatto") {
                    dismissKeyboard()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            loadSavedSettings()
        }
        .onDisappear {
            saveSettings()
        }
        .onChange(of: baseURL) { _, _ in saveSettings() }
        .onChange(of: userEmail) { _, _ in saveSettings() }
        .onChange(of: userPassword) { _, _ in saveSettings() }
        .onChange(of: googleAPIKey) { _, _ in saveSettings() }
    }

    private func loadSavedSettings() {
        baseURL = service.baseURL
        userEmail = service.userEmail
        userPassword = service.userPassword
        googleAPIKey = service.googleAPIKey
        isAuthenticated = service.isLoggedIn
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
            isAuthenticated = true
        } catch {
            loginStatus = error.localizedDescription
            loginSuccess = false
            isAuthenticated = false
        }

        isLoggingIn = false
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}