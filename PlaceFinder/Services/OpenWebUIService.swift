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
        isLoggedIn = true
        return token
    }

    // MARK: - Google Places Nearby Search

    /// Searches nearby places using the Google Places API (New).
    /// Uses `locationBias` for ranking by distance while still returning results beyond the radius.
    ///
    /// - Returns: A `PlacesSearchResult` containing the markdown summary.
    func searchNearbyPlaces(category: String, transitType: TransitType) async throws -> PlacesSearchResult {
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

        let markdown = parseGooglePlacesResponse(data: data, category: category)
        return PlacesSearchResult(markdown: markdown, isFallback: false)
    }

    /// Parses the raw Places API JSON response into markdown.
    private func parseGooglePlacesResponse(data: Data, category: String) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let places = json["places"] as? [[String: Any]],
              !places.isEmpty else {
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

    // MARK: - Available Models

    /// Fetches the list of available model IDs from the LiteLLM proxy's `/api/models`
    /// endpoint. Returns model IDs sorted alphabetically for the Picker dropdown.
    func fetchAvailableModels() async throws -> [String] {
        guard !baseURL.isEmpty else { throw ServiceError.missingBaseURL }
        guard let token = jwtToken else { throw ServiceError.notAuthenticated }

        let urlString = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/models"
        guard let url = URL(string: urlString) else { throw ServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ServiceError.chatCompletionFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            return []
        }

        return models.compactMap { $0["id"] as? String }.sorted()
    }

    // MARK: - Chat Completion

    /// Context about the user's current location and time, injected into every request.
    struct LocationContext {
        let latitude: Double
        let longitude: Double
        let timestamp: String
    }

    /// Sends a chat completion request to the server.
    ///
    /// When `googlePlacesContext` is provided, a concierge system prompt is injected
    /// that instructs the LLM to select and describe ONLY the top 5 venues from
    /// the real Google data, with clickable Google Maps links. Streaming is used.
    ///
    /// Without `googlePlacesContext`, this falls back to normal non-streaming chat
    /// with web search tools available.
    ///
    /// `locationContext` is injected as a system message so the LLM always knows
    /// the user's current position and time.
    func sendChatCompletion(
        model: String,
        messages: [ChatMessage],
        googlePlacesContext: String?,
        language: String? = nil,
        locationContext: LocationContext? = nil
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
        let hasPlaces = googlePlacesContext != nil && !googlePlacesContext!.isEmpty

        // ── Build location context string ──
        let locationInfo: String
        if let ctx = locationContext {
            locationInfo = "You are PlaceFinder, a helpful assistant. The user's current location is lat \(String(format: "%.6f", ctx.latitude)), lon \(String(format: "%.6f", ctx.longitude)). The current date/time is \(ctx.timestamp). Important: use this location and time to answer time- or location-dependent questions (weather, local time, nearby services, etc.) WITHOUT asking the user for their location. If the user's question does not require location, ignore this context."
        } else {
            locationInfo = ""
        }

        if hasPlaces {
            // ── Concierge prompt with Google Places data (top 5, streaming) ──
            let lang = (language == "EN") ? "English" : "Italian"
            let strictSystemPrompt = """
            Sei un concierge locale esperto. ANSWER ONLY IN: \(lang).
            Basandoti SOLO sulla lista reale di Google, seleziona un MASSIMO DI 5 LOCALI reali. \
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

            \(googlePlacesContext!)

            \(locationInfo)
            """
            payloadMessages.append([
                "role": "system",
                "content": strictSystemPrompt
            ])
        } else {
            // Normal chat: inject location context directly into the last user message
            // so the model cannot ignore it
            if !locationInfo.isEmpty {
                payloadMessages.append([
                    "role": "system",
                    "content": locationInfo
                ])
            }
            for (index, msg) in messages.enumerated() {
                let isLast = index == messages.count - 1
                let content: String
                if isLast && msg.role == .user && !locationInfo.isEmpty {
                    // Prepend location info to the last user message
                    let shortInfo = "You are PlaceFinder, a helpful assistant. The user's current location is lat \(String(format: "%.6f", locationContext!.latitude)), lon \(String(format: "%.6f", locationContext!.longitude)). The current date/time is \(locationContext!.timestamp). Important: use this location and time to answer time- or location-dependent questions (weather, local time, nearby services, etc.) WITHOUT asking the user for their location. If the user's question does not require location, ignore this context.\n\nUser message: "
                    content = shortInfo + msg.content
                } else {
                    content = msg.content
                }
                payloadMessages.append([
                    "role": msg.role.rawValue,
                    "content": content
                ])
            }
        }

        var payload: [String: Any] = [
            "model": model,
            "messages": payloadMessages,
            "stream": hasPlaces
        ]

        // For normal chat (non-streaming), inject web search tool definition
        if !hasPlaces {
            payload["tools"] = [
                [
                    "type": "function",
                    "function": [
                        "name": "litellm_web_search",
                        "description": "Search the web for real-time information",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "query": [
                                    "type": "string",
                                    "description": "Search query"
                                ]
                            ],
                            "required": ["query"]
                        ]
                    ]
                ]
            ]
            payload["tool_choice"] = "auto"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        if hasPlaces {
            // ── Streaming path (concierge with Places) ──
            let (streamData, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ServiceError.chatCompletionFailed
            }

            return AsyncThrowingStream<String, Error> { continuation in
                Task {
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
        } else {
            // ── Non-streaming path (normal chat with web search tools) ──
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ServiceError.chatCompletionFailed
            }

            let content = parseNonStreamingResponse(data)

            return AsyncThrowingStream<String, Error> { continuation in
                if !content.isEmpty {
                    continuation.yield(content)
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Intent Detection

    /// Queries the LLM to determine whether the user's message is asking to find/search
    /// for places/venues/locations. Returns the extracted search query if YES, nil if NO.
    func detectPlaceSearchIntent(userMessage: String) async -> String? {
        guard let token = jwtToken, !baseURL.isEmpty else { return nil }

        let urlString = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/chat/completions"
        guard let url = URL(string: urlString) else { return nil }

        let detectionPrompt = """
        Does this user message ask to find or search for places, venues, locations, shops, restaurants, bars, or other physical establishments? Reply EXACTLY with one of these two formats (nothing else):

        YES|<search query>
        NO

        Examples:
        "trova pizzerie" → YES|pizzerie
        "mi consigli un buon sushi a Milano?" → YES|sushi Milano
        "che tempo fa domani?" → NO
        "cosa ne pensi dei ristoranti stellati?" → NO
        "come stai?" → NO
        "cerco un bar vicino" → YES|bar vicino
        "hotel economici a Roma" → YES|hotel economici Roma

        Message: "\(userMessage)"
        """

        let messages: [[String: Any]] = [
            ["role": "user", "content": detectionPrompt]
        ]

        let payload: [String: Any] = [
            "model": "deepseek-v4-pro",
            "messages": messages,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            let content = parseNonStreamingResponse(data).trimmingCharacters(in: .whitespacesAndNewlines)
            if content.hasPrefix("YES|") {
                let query = String(content.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                return query.isEmpty ? nil : query
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    /// Extracts the content string from a non-streaming chat completion JSON response.
    private func parseNonStreamingResponse(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return ""
        }
        return content
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

/// Result of a Google Places nearby search.
struct PlacesSearchResult {
    let markdown: String
    let isFallback: Bool
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