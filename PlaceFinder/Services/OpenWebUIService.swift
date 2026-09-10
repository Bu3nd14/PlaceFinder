// Second Release
//  OpenWebUIService.swift
//  PlaceFinder
//
//  Created on 18.07.26.
//

import Foundation
import Combine
import Security

final class OpenWebUIService: ObservableObject {
    static let shared = OpenWebUIService()
    private static let defaultAPIBaseURL = "https://api.openai.com/v1"

    @Published var isConnected: Bool = false

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    // MARK: - Settings Keys

    private enum Keys {
        static let apiBaseURL = "com.placefinder.apiBaseURL"
        static let apiKey = "com.placefinder.apiKey"
        static let googleAPIKey = "com.placefinder.googleAPIKey"
    }

    // MARK: - Settings Persistence

    var apiBaseURL: String {
        get {
            let savedURL = UserDefaults.standard.string(forKey: Keys.apiBaseURL) ?? ""
            return savedURL.isEmpty ? Self.defaultAPIBaseURL : savedURL
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.apiBaseURL) }
    }

    var apiKey: String {
        get { SecureStorage.string(forKey: Keys.apiKey) ?? "" }
        set { SecureStorage.set(newValue, forKey: Keys.apiKey) }
    }

    var googleAPIKey: String {
        get {
            if let apiKey = SecureStorage.string(forKey: Keys.googleAPIKey) {
                return apiKey
            }

            // Move the previously persisted Google key out of UserDefaults.
            let legacyKey = UserDefaults.standard.string(forKey: Keys.googleAPIKey) ?? ""
            guard !legacyKey.isEmpty else { return "" }
            SecureStorage.set(legacyKey, forKey: Keys.googleAPIKey)
            UserDefaults.standard.removeObject(forKey: Keys.googleAPIKey)
            return legacyKey
        }
        set { SecureStorage.set(newValue, forKey: Keys.googleAPIKey) }
    }

    // MARK: - API Connection

    /// Verifies an OpenAI-compatible endpoint and API key by listing models.
    func verifyConnection() async throws {
        _ = try await fetchAvailableModels()
        isConnected = true
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
        request.setValue("places.id,places.displayName,places.formattedAddress,places.rating,places.name", forHTTPHeaderField: "X-Goog-FieldMask")
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
        let s = AppStrings.shared

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let places = json["places"] as? [[String: Any]],
              !places.isEmpty else {
            let template = s.noPlacesFound
            return template.replacingOccurrences(of: "%{category}", with: category)
        }

        let topPlaces = places.prefix(10)

        let titleTemplate = s.placesNearbyTitle
        var markdown = titleTemplate.replacingOccurrences(of: "%{category}", with: category) + "\n\n"

        for (index, place) in topPlaces.enumerated() {
            let placeID = (place["id"] as? String) ?? ""
            let displayName = (place["displayName"] as? [String: Any])?["text"] as? String ?? s.unknownPlaceName
            let address = (place["formattedAddress"] as? String) ?? ""
            let rating = place["rating"] as? Double

            markdown += "**\(index + 1). \(displayName)**\n"
            if !placeID.isEmpty {
                markdown += "- Place ID: \(placeID)\n"
            }
            if !address.isEmpty {
                markdown += s.addressLabel + address + "\n"
            }
            if let rating = rating {
                markdown += s.ratingLabel + String(format: "%.1f / 5.0", rating) + "\n"
            }
            markdown += "\n"
        }

        return markdown
    }

    // MARK: - Available Models

    /// Fetches model IDs from an OpenAI-compatible `/models` endpoint.
    func fetchAvailableModels() async throws -> [String] {
        guard !apiBaseURL.isEmpty else { throw ServiceError.missingBaseURL }
        guard !apiKey.isEmpty else { throw ServiceError.missingAPIKey }

        let urlString = apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models"
        guard let url = URL(string: urlString) else { throw ServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

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
    /// Without `googlePlacesContext`, this falls back to a normal non-streaming chat.
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
        guard !apiBaseURL.isEmpty else {
            throw ServiceError.missingBaseURL
        }
        guard !apiKey.isEmpty else { throw ServiceError.missingAPIKey }

        let urlString = apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
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

        let payload: [String: Any] = [
            "model": model,
            "messages": payloadMessages,
            "stream": hasPlaces
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        if hasPlaces {
            // ── Streaming path ──
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
            // ── Non-streaming path (normal chat) ──
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
    func detectPlaceSearchIntent(userMessage: String, model: String) async -> String? {
        guard !apiKey.isEmpty, !apiBaseURL.isEmpty else { return nil }

        let urlString = apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
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
            "model": model,
            "messages": messages,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

private enum SecureStorage {
    static func string(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        guard !value.isEmpty else { return }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(attributes as CFDictionary, nil)
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
    case invalidURL
    case missingAPIKey
    case missingGoogleAPIKey
    case googlePlacesRequestFailed
    case chatCompletionFailed

    var errorDescription: String? {
        let s = AppStrings.shared
        switch self {
        case .missingBaseURL:
            return s.missingBaseURL
        case .invalidURL:
            return s.invalidURL
        case .missingAPIKey:
            return s.missingAPIKey
        case .missingGoogleAPIKey:
            return s.missingGoogleAPIKey
        case .googlePlacesRequestFailed:
            return s.googlePlacesRequestFailed
        case .chatCompletionFailed:
            return s.chatCompletionFailed
        }
    }
}
