//  ChatView.swift
//  PlaceFinder
//
//  Created on 18.07.26.
//

import SwiftUI
import UIKit
import os.log

// MARK: - ChatView

struct ChatView: View {
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var service = OpenWebUIService.shared

    // MARK: - Model & Transit State

    @State private var availableModels: [String] = [
        "deepseek-v4-pro",
        "gpt-4o",
        "claude-3-5-sonnet",
        "gemini-2.0-flash",
        "llama-3.1-70b"
    ]
    @State private var isLoadingModels: Bool = false
    @State private var selectedModel: String = "gpt-places"
    @State private var selectedTransit: TransitType = .walking
    @State private var selectedLanguage: String = "IT"

    // MARK: - Chat State

    @State private var messages: [ChatMessage] = []
    @State private var currentInput: String = ""
    @State private var isStreaming = false
    @State private var streamedAssistantContent: String = ""
    @State private var mumblingMessageID: UUID?
    @State private var mumblingOpacity: Double = 0.4
    @State private var pulsingTask: Task<Void, Never>?
    @State private var currentStreamTask: Task<Void, Never>?
    @FocusState private var inputFocus: Bool

    // MARK: - Error & Clipboard State

    @State private var showError = false
    @State private var errorMessage: String = ""
    @State private var isManuallyCancelling = false
    @State private var showCopiedToast = false

    @State private var failedMessageIDs: Set<UUID> = []
    @State private var retryOffsets: [UUID: CGFloat] = [:]
    @State private var currentSuggestions: [Suggestion] = []
    @State private var isConfigExpanded = false

    // MARK: - Suggestion Model
    struct Suggestion: Identifiable {
        let id = UUID()
        let emoji: String
        let text: String
        let timeSlot: TimeSlot
        
        enum TimeSlot {
            case always, morning, day, evening
        }
    }
    
    private let suggestionPool: [Suggestion] = [
        // MARK: Always
        Suggestion(emoji: "🍕", text: "Trova ristoranti", timeSlot: .always),
        Suggestion(emoji: "🍣", text: "Sushi vicino a me", timeSlot: .always),
        Suggestion(emoji: "🍝", text: "Trattorie e osterie", timeSlot: .always),
        Suggestion(emoji: "🌮", text: "Street food nei dintorni", timeSlot: .always),
        Suggestion(emoji: "🥩", text: "Griglierie e bracerie", timeSlot: .always),
        Suggestion(emoji: "🍔", text: "Hamburgerie top", timeSlot: .always),
        
        // MARK: Mattina (6–12)
        Suggestion(emoji: "🥐", text: "Colazione vicino a me", timeSlot: .morning),
        Suggestion(emoji: "☕", text: "Caffetteria con wifi", timeSlot: .morning),
        Suggestion(emoji: "🍳", text: "Brunch nel weekend", timeSlot: .morning),
        Suggestion(emoji: "🧁", text: "Pasticcerie e dolci", timeSlot: .morning),
        
        // MARK: Sera (17–02)
        Suggestion(emoji: "🍸", text: "Locali e cocktail bar", timeSlot: .evening),
        Suggestion(emoji: "🍺", text: "Birrerie e pub", timeSlot: .evening),
        Suggestion(emoji: "🎵", text: "Musica dal vivo", timeSlot: .evening),
        Suggestion(emoji: "🍷", text: "Enoteche e wine bar", timeSlot: .evening),
        
        // MARK: Giorno (8–18)
        Suggestion(emoji: "🎭", text: "Musei e mostre", timeSlot: .day),
        Suggestion(emoji: "🎬", text: "Cinema vicino a me", timeSlot: .day),
        Suggestion(emoji: "📚", text: "Biblioteche e librerie", timeSlot: .day),
        Suggestion(emoji: "🌳", text: "Parchi e giardini", timeSlot: .day),
        Suggestion(emoji: "🏃", text: "Percorsi per correre", timeSlot: .day),
        Suggestion(emoji: "🚴", text: "Piste ciclabili vicine", timeSlot: .day),
        Suggestion(emoji: "🛍️", text: "Shopping nei dintorni", timeSlot: .day),
        
        // MARK: Servizi fissi (sempre)
        Suggestion(emoji: "🏨", text: "Hotel in zona", timeSlot: .always),
        Suggestion(emoji: "💊", text: "Farmacie aperte", timeSlot: .always),
        Suggestion(emoji: "🏦", text: "Bancomat più vicino", timeSlot: .always),
    ]

    private let suggestionPoolEN: [Suggestion] = [
        // MARK: Always
        Suggestion(emoji: "🍕", text: "Find restaurants", timeSlot: .always),
        Suggestion(emoji: "🍣", text: "Sushi near me", timeSlot: .always),
        Suggestion(emoji: "🍝", text: "Italian trattorias", timeSlot: .always),
        Suggestion(emoji: "🌮", text: "Street food nearby", timeSlot: .always),
        Suggestion(emoji: "🥩", text: "Steakhouses & grills", timeSlot: .always),
        Suggestion(emoji: "🍔", text: "Top burger joints", timeSlot: .always),

        // MARK: Morning (6–12)
        Suggestion(emoji: "🥐", text: "Breakfast near me", timeSlot: .morning),
        Suggestion(emoji: "☕", text: "Coffee shops with WiFi", timeSlot: .morning),
        Suggestion(emoji: "🍳", text: "Weekend brunch", timeSlot: .morning),
        Suggestion(emoji: "🧁", text: "Pastry shops & sweets", timeSlot: .morning),

        // MARK: Evening (17–02)
        Suggestion(emoji: "🍸", text: "Cocktail bars & lounges", timeSlot: .evening),
        Suggestion(emoji: "🍺", text: "Beer pubs & breweries", timeSlot: .evening),
        Suggestion(emoji: "🎵", text: "Live music venues", timeSlot: .evening),
        Suggestion(emoji: "🍷", text: "Wine bars & enotecas", timeSlot: .evening),

        // MARK: Daytime (8–18)
        Suggestion(emoji: "🎭", text: "Museums & exhibitions", timeSlot: .day),
        Suggestion(emoji: "🎬", text: "Cinemas near me", timeSlot: .day),
        Suggestion(emoji: "📚", text: "Libraries & bookstores", timeSlot: .day),
        Suggestion(emoji: "🌳", text: "Parks & gardens", timeSlot: .day),
        Suggestion(emoji: "🏃", text: "Running paths", timeSlot: .day),
        Suggestion(emoji: "🚴", text: "Bike routes nearby", timeSlot: .day),
        Suggestion(emoji: "🛍️", text: "Shopping nearby", timeSlot: .day),

        // MARK: Services (always)
        Suggestion(emoji: "🏨", text: "Hotels in the area", timeSlot: .always),
        Suggestion(emoji: "💊", text: "Open pharmacies", timeSlot: .always),
        Suggestion(emoji: "🏦", text: "Nearest ATM", timeSlot: .always),
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Config Bar pillow
            configBar
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.top, 8)
                .zIndex(1)

            // Chat messages + suggestions in one scrollable area
            ScrollViewReader { proxy in
                ScrollView {
                    if messages.isEmpty && !isStreaming {
                        welcomeView
                            .padding(.horizontal)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { msg in
                                if msg.id != mumblingMessageID {
                                    messageBubble(for: msg)
                                }
                            }

                            // Streaming mumbling
                            if let mumblingID = mumblingMessageID,
                               messages.contains(where: { $0.id == mumblingID }) {
                                MumblingBubble(opacity: mumblingOpacity)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("bottomAnchor")
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 8)
                .onChange(of: messages.count) { _ in
                    scrollToBottom(proxy: proxy, delay: 0.1)
                }
                .onChange(of: streamedAssistantContent) { _ in
                    scrollToBottom(proxy: proxy, delay: 0.05)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            inputBar
                .padding(.horizontal)
                .padding(.bottom, 8)
                .padding(.top, 8)
                .background(.regularMaterial)
        }
        .navigationTitle("PlaceFinder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    resetChat()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                }
            }
        }
        .toolbarBackground(Color.cyan.opacity(0.15), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            refreshSuggestions()
            Task { await reloadAvailableModels() }
        }
        .onChange(of: selectedLanguage) { _ in
            refreshSuggestions()
        }
        .alert("Errore", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Config Bar (Collapsible)

    private var configBar: some View {
        VStack(spacing: 8) {
            // Collapsed / Expanded toggle pill
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isConfigExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(shortConfigLabel)
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isConfigExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)

            if isConfigExpanded {
                Divider()
                    .padding(.horizontal, 4)

                // Row: Model picker
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if isLoadingModels {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Picker("Model", selection: $selectedModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                    .tint(.primary)
                }

                // Row: Transit + Language
                HStack(spacing: 12) {
                    Picker("Mezzo", selection: $selectedTransit) {
                        Text("A piedi").tag(TransitType.walking)
                        Text("In auto").tag(TransitType.driving)
                    }
                    .pickerStyle(.segmented)
                    .scaleEffect(0.85)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Lingua", selection: $selectedLanguage) {
                            Text("IT").tag("IT")
                            Text("EN").tag("EN")
                        }
                        .pickerStyle(.segmented)
                        .scaleEffect(0.85)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var shortConfigLabel: String {
        let transitText = selectedTransit == .walking ? "A piedi" : "In auto"
        return "🧠 \(selectedModel.components(separatedBy: "-").first ?? selectedModel) · \(transitText) · \(selectedLanguage)"
    }

    // MARK: - Welcome View (Suggestions)

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            Text("👋 Cosa vuoi cercare?")
                .font(.title3.weight(.semibold))
            Text("Tocca un suggerimento o scrivi liberamente")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(currentSuggestions) { suggestion in
                Button {
                    currentInput = suggestion.text
                    sendMessage()
                } label: {
                    HStack {
                        Text(suggestion.emoji)
                        Text(suggestion.text)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 32)
                .disabled(isStreaming)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Message Bubble

    @ViewBuilder
    private func messageBubble(for msg: ChatMessage) -> some View {
        VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: 4) {
            HStack(alignment: .top) {
                if msg.role == .user { Spacer(minLength: 60) }

                VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: 6) {
                    if msg.role == .assistant {
                        MarkdownWebView(markdown: msg.content)
                            .frame(minHeight: 24)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        Text(msg.content)
                            .font(.body)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 16))
                    }

                    // Retry button for failed user messages
                    if msg.role == .user && failedMessageIDs.contains(msg.id) {
                        Button {
                            retryMessage(msg.id)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption2)
                                Text("Riprova")
                                    .font(.caption2)
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1), in: Capsule())
                        }
                    }
                }
                .contextMenu {
                    if msg.role == .assistant {
                        Button {
                            copyToClipboard(msg.content)
                        } label: {
                            Label("Copia", systemImage: "doc.on.doc")
                        }
                    }
                }

                if msg.role == .assistant { Spacer(minLength: 60) }
            }
        }
        .id(msg.id)
    }

    // MARK: - Mumbling Bubble

    struct MumblingBubble: View {
        let opacity: Double

        var body: some View {
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.secondary.opacity(opacity))
                        .frame(width: 6, height: 6)
                    Circle()
                        .fill(Color.secondary.opacity(max(opacity - 0.15, 0.1)))
                        .frame(width: 6, height: 6)
                    Circle()
                        .fill(Color.secondary.opacity(max(opacity - 0.3, 0.1)))
                        .frame(width: 6, height: 6)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                Spacer(minLength: 60)
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Chiedi qualsiasi cosa...", text: $currentInput, axis: .vertical)
                .focused($inputFocus)
                .lineLimit(1...6)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .onSubmit { sendMessage() }

            if isStreaming {
                Button {
                    cancelStreaming()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
            } else {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .blue)
                }
                .disabled(currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Send Message

    private func sendMessage() {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let userMsgID = UUID()
        let userMessage = ChatMessage(id: userMsgID, role: .user, content: trimmed)
        messages.append(userMessage)
        currentInput = ""
        inputFocus = false

        // Start pulsing mumbling
        let mumblingID = UUID()
        let mumblingMessage = ChatMessage(id: mumblingID, role: .assistant, content: "")
        messages.append(mumblingMessage)
        mumblingMessageID = mumblingID
        startPulsing()

        isStreaming = true
        streamedAssistantContent = ""

        let model = selectedModel
        let transit = selectedTransit

        currentStreamTask = Task {
            var accumulated = ""

            // Begin background task so the request survives ~30 s after the app loses focus
            var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
            backgroundTaskID = await UIApplication.shared.beginBackgroundTask(withName: "PlaceFinder.chat") {
                // Expiration handler – cancel the task if the system is about to kill us
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }

            do {
                let t0 = CFAbsoluteTimeGetCurrent()

                // 1) Run intent detection to decide whether to call Places
                // 2) If intent detected, call Places and use concierge streaming prompt
                let placesContext: String?
                let t_detect = CFAbsoluteTimeGetCurrent()
                if let detectedQuery = await service.detectPlaceSearchIntent(userMessage: trimmed) {
                    let t_detect_end = CFAbsoluteTimeGetCurrent()
                    os_log("⏱️ detectPlaceSearchIntent: %.2fs", t_detect_end - t_detect)
                    if let result = try? await service.searchNearbyPlaces(category: detectedQuery, transitType: transit) {
                        placesContext = result.markdown
                        let t_places = CFAbsoluteTimeGetCurrent()
                        os_log("⏱️ searchNearbyPlaces: %.2fs", t_places - t_detect_end)
                    } else {
                        placesContext = nil
                        let t_places = CFAbsoluteTimeGetCurrent()
                        os_log("⏱️ searchNearbyPlaces (failed): %.2fs", t_places - t_detect_end)
                    }
                } else {
                    let t_detect_end = CFAbsoluteTimeGetCurrent()
                    os_log("⏱️ detectPlaceSearchIntent (no match): %.2fs", t_detect_end - t_detect)
                    placesContext = nil
                }

                // Await GPS fix to guarantee we have coordinates
                let t_before_gps = CFAbsoluteTimeGetCurrent()
                let locationContext: OpenWebUIService.LocationContext?
                if let (lat, lon) = try? await locationManager.fetchCurrentCoordinates() {
                    let t_gps = CFAbsoluteTimeGetCurrent()
                    os_log("⏱️ GPS fetch: %.2fs", t_gps - t_before_gps)
                    let formatter = ISO8601DateFormatter()
                    formatter.timeZone = TimeZone.current
                    formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
                    locationContext = OpenWebUIService.LocationContext(
                        latitude: lat,
                        longitude: lon,
                        timestamp: formatter.string(from: Date())
                    )
                } else {
                    let t_gps = CFAbsoluteTimeGetCurrent()
                    os_log("⏱️ GPS fetch (failed): %.2fs", t_gps - t_before_gps)
                    locationContext = nil
                }
                let t_before_llm = CFAbsoluteTimeGetCurrent()
                let stream = try await service.sendChatCompletion(
                    model: model,
                    messages: messages,
                    googlePlacesContext: placesContext,
                    language: selectedLanguage,
                    locationContext: locationContext
                )
                let t_llm_ttfb = CFAbsoluteTimeGetCurrent()
                os_log("⏱️ LLM concierge TTFB: %.2fs", t_llm_ttfb - t_before_llm)

                let streamTask = Task {
                    var lastUpdate = Date()
                    for try await chunk in stream {
                        try Task.checkCancellation()
                        accumulated += chunk
                        let now = Date()
                        if now.timeIntervalSince(lastUpdate) > 0.05 {
                            let snapshot = accumulated
                            await MainActor.run { streamedAssistantContent = snapshot }
                            lastUpdate = now
                        }
                    }
                    await MainActor.run { streamedAssistantContent = accumulated }
                }

                let timeoutTask = Task {
                    try await Task.sleep(nanoseconds: 90 * 1_000_000_000)
                    streamTask.cancel()
                }

                // Wait for the stream to finish; the first to finish determines the outcome
                _ = await streamTask.result
                timeoutTask.cancel()
                let t_end = CFAbsoluteTimeGetCurrent()
                os_log("⏱️ LLM concierge streaming: %.2fs | TOTAL: %.2fs", t_end - t_llm_ttfb, t_end - t0)
            } catch {
                if await MainActor.run(body: { isManuallyCancelling }) {
                    // User pressed Stop or Reset — no alert
                    await MainActor.run { isManuallyCancelling = false }
                } else if error is CancellationError {
                    // Timed out
                    if accumulated.isEmpty {
                        accumulated = selectedLanguage == "EN"
                            ? "Response timed out. Please try again."
                            : "Risposta scaduta. Riprova."
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Chat fallita: \(error.localizedDescription)"
                        showError = true
                        if accumulated.isEmpty {
                            failedMessageIDs.insert(userMsgID)
                        }
                    }
                }
            }

            // End the background task
            if backgroundTaskID != .invalid {
                await UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }

            await MainActor.run {
                messages.removeAll { $0.id == mumblingID }
                mumblingMessageID = nil
                stopPulsing()
                if !accumulated.isEmpty {
                    messages.append(ChatMessage(role: .assistant, content: accumulated))
                }
                streamedAssistantContent = ""
                isStreaming = false
                currentStreamTask = nil
            }
        }
    }

    // MARK: - Pulsing

    private func startPulsing() {
        mumblingOpacity = 0.4
        pulsingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        mumblingOpacity = mumblingOpacity == 0.4 ? 0.85 : 0.4
                    }
                }
            }
        }
    }

    private func stopPulsing() {
        pulsingTask?.cancel()
        pulsingTask = nil
    }

    // MARK: - Scroll

    private func scrollToBottom(proxy: ScrollViewProxy, delay: Double) {
        Task {
            try? await Task.sleep(for: .milliseconds(delay * 1000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
            }
        }
    }

    // MARK: - Clipboard & Haptics

    private func copyToClipboard(_ content: String) {
        UIPasteboard.general.string = content
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        withAnimation(.easeInOut(duration: 0.25)) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showCopiedToast = false
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func resetChat() {
        isManuallyCancelling = true
        currentStreamTask?.cancel()
        currentStreamTask = nil
        stopPulsing()
        withAnimation(.easeInOut(duration: 0.25)) {
            messages.removeAll()
            streamedAssistantContent = ""
            failedMessageIDs.removeAll()
            retryOffsets.removeAll()
            mumblingMessageID = nil
            isStreaming = false
            refreshSuggestions()
        }
    }

    private func cancelStreaming() {
        isManuallyCancelling = true
        currentStreamTask?.cancel()
        currentStreamTask = nil
        stopPulsing()
        withAnimation(.easeInOut(duration: 0.25)) {
            messages.removeAll { $0.id == mumblingMessageID }
            mumblingMessageID = nil
            isStreaming = false
            streamedAssistantContent = ""
        }
    }

    // MARK: - Suggestions

    private func refreshSuggestions() {
        let hour = Calendar.current.component(.hour, from: Date())
        
        let timeSlot: Suggestion.TimeSlot
        switch hour {
        case 6..<12:  timeSlot = .morning
        case 17..<24, 0..<2: timeSlot = .evening
        case 8..<18: timeSlot = .day
        default: timeSlot = .always
        }
        
        let pool = selectedLanguage == "EN" ? suggestionPoolEN : suggestionPool
        var weighted: [Suggestion] = []
        for s in pool {
            if s.timeSlot == .always {
                weighted.append(contentsOf: Array(repeating: s, count: 3))
            } else if s.timeSlot == timeSlot {
                weighted.append(contentsOf: Array(repeating: s, count: 3))
            } else {
                weighted.append(s)
            }
        }
        
        var picked: [Suggestion] = []
        var usedIDs = Set<UUID>()
        let shuffled = weighted.shuffled()
        for s in shuffled {
            guard picked.count < 3 else { break }
            if !usedIDs.contains(s.id) {
                picked.append(s)
                usedIDs.insert(s.id)
            }
        }
        currentSuggestions = picked
    }

    // MARK: - Retry

    private func retryMessage(_ userMsgID: UUID) {
        guard !isStreaming else { return }

        guard let userMessage = messages.first(where: { $0.id == userMsgID }),
              userMessage.role == .user else { return }

        if let idx = messages.firstIndex(where: { $0.id == userMsgID }) {
            messages.removeSubrange(idx...)
        }

        failedMessageIDs.remove(userMsgID)
        retryOffsets.removeValue(forKey: userMsgID)

        currentInput = userMessage.content
        sendMessage()
    }

    private func reloadAvailableModels() async {
        isLoadingModels = true
        do {
            let models = try await service.fetchAvailableModels()
            guard !models.isEmpty else { return }
            await MainActor.run {
                availableModels = models
                if !models.contains(selectedModel) {
                    selectedModel = models[0]
                }
            }
        } catch {}
        await MainActor.run { isLoadingModels = false }
    }
}

// MARK: - TransitType Icon Helper

private extension TransitType {
    var iconName: String {
        switch self {
        case .walking: return "figure.walk"
        case .driving: return "car.fill"
        }
    }
}

// MARK: - Conditional View Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    NavigationStack {
        ChatView()
    }
}