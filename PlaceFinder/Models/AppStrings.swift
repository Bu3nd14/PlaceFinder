//  AppStrings.swift
//  PlaceFinder
//
//  Created on 19.07.26.
//

import Foundation
import Combine

/// Centralized UI strings with English/Italian support.
/// Set `language` to "EN" or "IT" to switch all UI text at once.
final class AppStrings: ObservableObject {
    static let shared = AppStrings()

    @Published var language: String = "IT"

    private init() {}

    // MARK: - Tab Labels

    var settingsTab: String { language == "EN" ? "Settings" : "Impostazioni" }

    // MARK: - ChatView

    var errorTitle: String { language == "EN" ? "Error" : "Errore" }
    var walkingLabel: String { language == "EN" ? "Walking" : "A piedi" }
    var drivingLabel: String { language == "EN" ? "By car" : "In auto" }
    var modePickerLabel: String { language == "EN" ? "Mode" : "Mezzo" }
    var languagePickerLabel: String { language == "EN" ? "Language" : "Lingua" }
    var welcomeTitle: String { language == "EN" ? "👋 What are you looking for?" : "👋 Cosa vuoi cercare?" }
    var welcomeSubtitle: String { language == "EN" ? "Tap a suggestion or type freely" : "Tocca un suggerimento o scrivi liberamente" }
    var inputPlaceholder: String { language == "EN" ? "Ask me anything..." : "Chiedi qualsiasi cosa..." }
    var retryButton: String { language == "EN" ? "Retry" : "Riprova" }
    var copyButton: String { language == "EN" ? "Copy" : "Copia" }
    var chatFailedPrefix: String { language == "EN" ? "Chat failed: " : "Chat fallita: " }

    // MARK: - SettingsView

    var connectionSection: String { language == "EN" ? "Connection" : "Connessione" }
    var connectionSubtitle: String { language == "EN" ? "OpenAI-compatible API base URL and key" : "URL base e chiave API compatibili OpenAI" }
    var apiBaseURLPlaceholder: String { language == "EN" ? "API Base URL (e.g. https://api.openai.com/v1)" : "URL base API (es. https://api.openai.com/v1)" }
    var apiKeyPlaceholder: String { language == "EN" ? "API Key" : "Chiave API" }
    var connectButton: String { language == "EN" ? "Connect" : "Connetti" }
    var connectedBadge: String { language == "EN" ? "Connected ✓" : "Connesso ✓" }
    var connectionSuccess: String { language == "EN" ? "Connection verified." : "Connessione verificata." }
    var googlePlacesSection: String { language == "EN" ? "Google Places API" : "Google Places API" }
    var googleAPIHint: String { language == "EN" ? "Key to search nearby places" : "Chiave per ricercare luoghi nelle vicinanze" }
    var googleAPIKeyPlaceholder: String { language == "EN" ? "Google API Key" : "Google API Key" }
    var googleAPIKeyStorageHint: String { language == "EN" ? "The key is stored securely on this device and used for nearby searches." : "La chiave viene salvata in modo sicuro su questo dispositivo e usata per cercare luoghi nelle vicinanze." }
    var infoSection: String { language == "EN" ? "Information" : "Informazioni" }
    var infoText: String {
        language == "EN"
            ? "PlaceFinder uses the Google Places API to search for places near your location and an LLM to provide personalized recommendations."
            : "PlaceFinder utilizza l'API Google Places per cercare luoghi vicino alla tua posizione e un LLM per fornire raccomandazioni personalizzate."
    }

    // MARK: - LocationManager Errors

    var permissionDeniedError: String {
        language == "EN"
            ? "Location access denied. Enable it in Settings."
            : "Accesso alla posizione negato. Abilitalo nelle Impostazioni."
    }

    var unknownLocationError: String {
        language == "EN"
            ? "Unknown error retrieving location."
            : "Errore sconosciuto nel recupero della posizione."
    }

    // MARK: - AI Service Error Descriptions

    var missingBaseURL: String {
        language == "EN" ? "Base URL not configured. Go to Settings." : "Base URL non configurato. Vai nelle Impostazioni."
    }
    var missingAPIKey: String { language == "EN" ? "API key not configured. Go to Settings." : "Chiave API non configurata. Vai nelle Impostazioni." }
    var invalidURL: String { language == "EN" ? "Invalid URL." : "URL non valido." }
    var missingGoogleAPIKey: String {
        language == "EN" ? "Google Places API Key not configured. Go to Settings." : "Google Places API Key non configurata. Vai nelle Impostazioni."
    }
    var googlePlacesRequestFailed: String {
        language == "EN" ? "Google Places request failed." : "Richiesta a Google Places fallita."
    }
    var chatCompletionFailed: String {
        language == "EN" ? "Chat request failed." : "Richiesta di chat fallita."
    }

    // MARK: - Google Places Parse Strings

    var noPlacesFound: String { language == "EN" ? "No places found for category \"%{category}\"." : "Nessun luogo trovato per la categoria \"%{category}\"." }
    var placesNearbyTitle: String { language == "EN" ? "### Nearby places for: %{category}" : "### Luoghi nelle vicinanze per: %{category}" }
    var unknownPlaceName: String { language == "EN" ? "Unknown" : "Sconosciuto" }
    var addressLabel: String { language == "EN" ? "- Address: " : "- Indirizzo: " }
    var isOpenLabel: String { language == "EN" ? "- Open now: " : "- Aperto adesso: " }
    var ratingLabel: String { language == "EN" ? "- Rating: " : "- Valutazione: " }
}
