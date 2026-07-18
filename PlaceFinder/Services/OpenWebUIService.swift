// Second Release
//  OpenWebUIService.swift
//  PlaceFinder
//
//  Created on 18.07.26.
//

import Foundation
import Combine

final class OpenWebUIService: ObservableObject {
    static let shared = OpenWebUIService()

    @Published var isLoggedIn: Bool = false

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    // MARK: - Secure Storage Keys

    private enum Keys {
        static let baseURL = "com.placefinder.baseURL"
        static let userEmail = "com.placefinder.userEmail"
        static let userPassword = "com.placefinder.userPassword"
        static let googleAPIKey = "com.placefinder.googleAPIKey"
        static let jwtToken = "com.placefinder.jwtToken"
    }

    // MARK: - Settings Persistence

    var baseURL: String {
        get { UserDefaults.standard.string(forKey: Keys.baseURL) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.baseURL) }
    }

    var userEmail: String {
        get { UserDefaults.standard.string(forKey: Keys.userEmail) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.userEmail) }
    }

    var userPassword: String {
        get { UserDefaults.standard.string(forKey: Keys.userPassword) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.userPassword) }
    }

    var googleAPIKey: String {
        get { UserDefaults.standard.string(forKey: Keys.googleAPIKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.googleAPIKey) }
    }

    private var jwtToken: String? {
        get { UserDefaults.standard.string(forKey: Keys.jwtToken) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.jwtToken) }
    }

    // MARK: - JWT Authentication

    /// Logs into the server and caches the JWT token securely.
    /// - Returns: The JWT token string.
    func loginToServer() async throws -> String {
        guard !baseURL.isEmpty else {
            throw ServiceError.missingBaseURL
        }
        guard !userEmail.isEmpty, !userPassword.isEmpty else {
            throw ServiceError.missingCredentials
        }

        let urlString = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v1/auths/signin"
        guard let url = URL(string: urlString) else {
            throw ServiceError.invalidURL
        }

        let body: [String: String] = [
            "email": userEmail,
            "password": userPassword
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ServiceError.loginFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String else {
            throw ServiceError.invalidTokenResponse
        }

        jwtToken = token
        return token
    }

    // MARK: - Google Places Nearby Search

    /// Searches nearby places using the Google Places API (New) and returns a formatted
    /// raw markdown summary string ready to be appended into the LLM message context.
    func searchNearbyPlaces(category: String, transitType: TransitType) async throws -> String {
        let apiKey = googleAPIKey
        guard !apiKey.isEmpty else {
            throw ServiceError.missingGoogleAPIKey
        }

        let (latitude, longitude) = try await LocationManager.shared.fetchCurrentCoordinates()

        let radius = transitType.radiusInMeters

        guard let url = URL(string: "https://places.googleapis.com/v1/places:searchText") else {
            throw ServiceError.invalidURL
        }

        let requestBody: [String: Any] = [
            "textQuery": "\(category) vicino a me",
            "maxResultCount": 10,
            "locationBias": [
                "circle": [
                    "center": [
                        "latitude": latitude,
                        "longitude": longitude
                    ],
                    "radius": Double(radius)
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.id,places.displayName,places.formattedAddress,places.rating", forHTTPHeaderField: "X-Goog-FieldMask")
        request.setValue("RC.PlaceFinder", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ServiceError.googlePlacesRequestFailed
        }

        return parseGooglePlacesResponse(data: data, category: category)
    }

    private func parseGooglePlacesResponse(data: Data, category: String) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let places = json["places"] as? [[String: Any]] else {
            return "Nessun luogo trovato per la categoria \"\(category)\"."
        }

        let topPlaces = places.prefix(10)

        var markdown = "### Luoghi nelle vicinanze per: \(category)\n\n"

        for (index, place) in topPlaces.enumerated() {
            let placeID = (place["id"] as? String) ?? ""
            let displayName = (place["displayName"] as? [String: Any])?["text"] as? String ?? "Sconosciuto"
            let address = (place["formattedAddress"] as? String) ?? ""
            let rating = place["rating"] as? Double

            markdown += "**\(index + 1). \(displayName)**\n"
            if !placeID.isEmpty {
                markdown += "- Place ID: \(placeID)\n"
            }
            if !address.isEmpty {
                markdown += "- Indirizzo: \(address)\n"
            }
            if let rating = rating {
                markdown += "- Valutazione: \(String(format: "%.1f / 5.0", rating))\n"
            }
            markdown += "\n"
        }

        return markdown
    }

    // MARK: - Chat Completion (Streaming)

    /// Sends a chat completion request to the server with streaming enabled.
    ///
    /// When `autoSearchCategory` and `autoSearchTransit` are provided alongside
    /// `googlePlacesContext`, a strict hidden concierge system prompt is assembled
    /// that instructs the LLM to select and describe ONLY the top 3 venues from
    /// the real Google data. The user-visible `messages` are omitted from the
    /// payload in this mode so the chat UI stays clean.
    func sendChatCompletion(
        model: String,
        messages: [ChatMessage],
        googlePlacesContext: String?,
        autoSearchCategory: String? = nil,
        autoSearchTransit: String? = nil,
        autoSearchLanguage: String? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let token = jwtToken else {
            throw ServiceError.notAuthenticated
        }
        guard !baseURL.isEmpty else {
            throw ServiceError.missingBaseURL
        }

        let urlString = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/chat/completions"
        guard let url = URL(string: urlString) else {
            throw ServiceError.invalidURL
        }

        var payloadMessages: [[String: Any]] = []

        let isAutoSearch = (autoSearchCategory != nil && autoSearchTransit != nil)

        if isAutoSearch, let context = googlePlacesContext, !context.isEmpty {
            // ── Hidden concierge prompt with embedded Google data ──
            let language = (autoSearchLanguage == "EN") ? "Inglese" : "Italiano"
            let strictSystemPrompt = """
            Sei un concierge locale esperto. L'utente sta cercando la categoria '\(autoSearchCategory!)' \
            raggiungibile '\(autoSearchTransit!)'. RISPONDI ESCLUSIVAMENTE NELLA LINGUA: \(language).
            Basandoti SOLO sulla lista reale di Google, seleziona un MASSIMO DI 3 LOCALI reali. \
            Sii ESTREMAMENTE SINTETICO. Per ogni locale, il nome DEVE essere un link cliccabile \
            markdown usando esattamente il nome e il Place ID forniti nei dati, con questa \
            struttura URL OBBLIGATORIA (non inventare altri formati): \
            [**NOME_LOCALE**](https://www.google.com/maps/search/?api=1&query=NOME_URL_ENCODED&query_place_id=PLACE_ID). \
            IMPORTANTE: sostituisci NOME_URL_ENCODED con il nome del locale sostituendo gli \
            spazi con il segno + (esempio: Garden+Cafe). PLACE_ID deve essere il valore \
            esatto del campo Place ID riportato nei dati.
            Sotto il link, mostra il punteggio, l'indirizzo e una singola frase di descrizione \
            fulminea (massimo 15 parole per locale). Elimina qualsiasi introduzione o conclusione, \
            vai dritto ai locali. Ecco i dati di Google con i rispettivi Place ID:

            \(context)
            """
            payloadMessages.append([
                "role": "system",
                "content": strictSystemPrompt
            ])
            // No user-visible messages injected — UI stays clean
        } else {
            // Standard chat path: inject Google Places as a gentle system prefix, then user messages
            if let context = googlePlacesContext, !context.isEmpty {
                payloadMessages.append([
                    "role": "system",
                    "content": "Sei un assistente utile. Ecco i luoghi trovati nelle vicinanze:\n\n\(context)"
                ])
            }

            for msg in messages {
                payloadMessages.append([
                    "role": msg.role.rawValue,
                    "content": msg.content
                ])
            }
        }

        let payload: [String: Any] = [
            "model": model,
            "messages": payloadMessages,
            "stream": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (streamData, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ServiceError.chatCompletionFailed
        }

        return AsyncThrowingStream<String, Error> { continuation in
            Task {
                var buffer = ""
                for try await line in streamData.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let jsonString = String(line.dropFirst(6))

                    if jsonString == "[DONE]" {
                        continuation.finish()
                        return
                    }

                    guard let data = jsonString.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let firstChoice = choices.first,
                          let delta = firstChoice["delta"] as? [String: Any],
                          let content = delta["content"] as? String else {
                        continue
                    }

                    continuation.yield(content)
                }
                continuation.finish()
            }
        }
    }
}

// MARK: - Supporting Types

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String

    init(id: UUID = UUID(), role: MessageRole, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

enum ServiceError: LocalizedError {
    case missingBaseURL
    case missingCredentials
    case invalidURL
    case loginFailed
    case invalidTokenResponse
    case missingGoogleAPIKey
    case googlePlacesRequestFailed
    case notAuthenticated
    case chatCompletionFailed

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "Base URL non configurato. Vai nelle Impostazioni."
        case .missingCredentials:
            return "Email o password non configurati. Vai nelle Impostazioni."
        case .invalidURL:
            return "URL non valido."
        case .loginFailed:
            return "Login fallito. Verifica le credenziali."
        case .invalidTokenResponse:
            return "Risposta di login non valida: token JWT mancante."
        case .missingGoogleAPIKey:
            return "Google Places API Key non configurata. Vai nelle Impostazioni."
        case .googlePlacesRequestFailed:
            return "Richiesta a Google Places fallita."
        case .notAuthenticated:
            return "Non autenticato. Effettua il login prima di inviare messaggi."
        case .chatCompletionFailed:
            return "Richiesta di chat fallita."
        }
    }
}