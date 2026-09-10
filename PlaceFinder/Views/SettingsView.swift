//
//  SettingsView.swift
//  PlaceFinder
//
//  Created on 18.07.26.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var service = OpenWebUIService.shared
    @StateObject private var strings = AppStrings.shared

    @State private var apiBaseURL: String = ""
    @State private var apiKey: String = ""
    @State private var googleAPIKey: String = ""
    @State private var isConnecting = false
    @State private var connectionStatus: String?
    @State private var connectionSuccess = false
    @State private var isConnected = false

    var body: some View {
        Form {
            // MARK: Server Section
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label(strings.connectionSection, systemImage: "server.rack")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                    Text(strings.connectionSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                TextField(strings.apiBaseURLPlaceholder, text: $apiBaseURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                SecureField(strings.apiKeyPlaceholder, text: $apiKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                if isConnected {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                        Text(strings.connectedBadge)
                            .font(.caption.weight(.medium))
                            .foregroundColor(.green)
                    }
                }

                Button {
                    Task { await verifyConnection() }
                } label: {
                    HStack {
                        if isConnecting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        }
                        Text(strings.connectButton)
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
                .disabled(isConnecting || apiBaseURL.isEmpty || apiKey.isEmpty)
                .opacity(apiBaseURL.isEmpty || apiKey.isEmpty ? 0.5 : 1)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))

                if let status = connectionStatus {
                    HStack(spacing: 6) {
                        Image(systemName: connectionSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(connectionSuccess ? .green : .red)
                        Text(status)
                            .font(.caption.weight(.medium))
                            .foregroundColor(connectionSuccess ? .green : .red)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill((connectionSuccess ? Color.green : Color.red).opacity(0.1))
                    )
                }
            }

            // MARK: Google Places Section
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label(strings.googlePlacesSection, systemImage: "map.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                    Text(strings.googleAPIHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                SecureField(strings.googleAPIKeyPlaceholder, text: $googleAPIKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                Text(strings.googleAPIKeyStorageHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // MARK: Info Section
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label(strings.infoSection, systemImage: "info.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                Text(strings.infoText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(strings.settingsTab)
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
        .onChange(of: apiBaseURL) { _, _ in saveSettings() }
        .onChange(of: apiKey) { _, _ in saveSettings() }
        .onChange(of: googleAPIKey) { _, _ in saveSettings() }
    }

    private func loadSavedSettings() {
        apiBaseURL = service.apiBaseURL
        apiKey = service.apiKey
        googleAPIKey = service.googleAPIKey
        isConnected = service.isConnected
    }

    private func saveSettings() {
        service.apiBaseURL = apiBaseURL
        service.apiKey = apiKey
        service.googleAPIKey = googleAPIKey
    }

    private func verifyConnection() async {
        isConnecting = true
        connectionStatus = nil
        connectionSuccess = false
        saveSettings()

        do {
            try await service.verifyConnection()
            connectionStatus = strings.connectionSuccess
            connectionSuccess = true
            isConnected = true
        } catch {
            connectionStatus = error.localizedDescription
            connectionSuccess = false
            isConnected = false
        }

        isConnecting = false
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
