// Frist Release
//  ChatView.swift
//  PlaceFinder
//
//  Created on 18.07.26.
//

import SwiftUI

struct ChatView: View {
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var service = OpenWebUIService.shared

    // MARK: - Model & Transit State

    /// The available model IDs the user can pick from. The first value is the default.
    private let availableModels = [
        "deepseek-v4-pro",
        "gpt-4o",
        "claude-3-5-sonnet",
        "gemini-2.0-flash",
        "llama-3.1-70b"
    ]

    @State private var selectedModel: String = "deepseek-v4-pro"

    @State private var selectedTransit: TransitType = .walking
    @State private var selectedLanguage: String = "IT"
    @State private var categoryText: String = ""

    // MARK: - Chat State

    @State private var messages: [ChatMessage] = []
    @State private var currentInput: String = ""
    @State private var isStreaming = false
    @State private var streamedAssistantContent: String = ""

    // MARK: - Error State

    @State private var showError = false
    @State private var errorMessage: String = ""
    @State private var showCopiedToast = false
    @State private var copiedBubbleScale = false

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // MARK: Title & Reset Header
                headerBar

                Divider()

                // MARK: Configuration Bar
                configBar

                Divider()

                // MARK: Message List
                messageList

                Divider()

                // MARK: Input Bar
                inputBar
            }
            .navigationBarHidden(true)
            .alert("Errore", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                locationManager.requestPermission()
            }
            // "Copiato!" Toast Overlay
            if showCopiedToast {
                Text("Copiato!")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(Color.black.opacity(0.7), in: Capsule())
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Header Bar (Title + Reset)

    private var headerBar: some View {
        HStack {
            Text("PlaceFinder")
                .font(.largeTitle.weight(.bold))

            Spacer()

            Button {
                resetChat()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title2)
            }
            .disabled(isStreaming)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Configuration Bar

    private var configBar: some View {
        VStack(spacing: 8) {
            // Row 1: Model selector
            HStack {
                Text("Modello:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Modello", selection: $selectedModel) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            // Row 2: Full-width Categoria field + search button
            HStack {
                Text("Categoria:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("es. ristoranti, bar, hotel...", text: $categoryText)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .autocorrectionDisabled()

                Button {
                    performAutoSearch()
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .disabled(categoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming)
            }

            // Row 3: Transit (leading) and Language (trailing) pickers
            HStack {
                Picker("Transito", selection: $selectedTransit) {
                    ForEach(TransitType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()

                Picker("Lingua", selection: $selectedLanguage) {
                    Text("IT").tag("IT")
                    Text("EN").tag("EN")
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        chatBubble(for: message)
                            .simultaneousGesture(
                                TapGesture()
                                    .onEnded { _ in
                                        dismissKeyboard()
                                    }
                            )
                    }

                    // Streaming placeholder
                    if isStreaming && !streamedAssistantContent.isEmpty {
                        chatStreamingBubble(content: streamedAssistantContent)
                    }

                    // Invisible anchor to scroll to bottom
                    Color.clear
                        .frame(height: 1)
                        .id("bottomAnchor")
                }
                .padding()
            }
            .onChange(of: messages.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: streamedAssistantContent) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Chiedi qualcosa...", text: $currentInput)
                .textFieldStyle(.roundedBorder)
                .disabled(isStreaming)
                .onSubmit {
                    sendMessage()
                }

            if isStreaming {
                Button(role: .destructive) {
                    // Stop streaming — we reset the streaming state
                    isStreaming = false
                    // Append whatever was streamed so far as an assistant message
                    if !streamedAssistantContent.isEmpty {
                        messages.append(ChatMessage(role: .assistant, content: streamedAssistantContent))
                        streamedAssistantContent = ""
                    }
                } label: {
                    Image(systemName: "stop.fill")
                }
            } else {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Chat Bubble

    @ViewBuilder
    private func chatBubble(for message: ChatMessage) -> some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
                userBubble(content: message.content)
            } else {
                assistantBubble(content: message.content, messageID: message.id)
                Spacer(minLength: 60)
            }
        }
    }

    private func userBubble(content: String) -> some View {
        Text(content)
            .padding(12)
            .background(Color.blue)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func assistantBubble(content: String, messageID: UUID) -> some View {
        Text(LocalizedStringKey(content))
            .padding(12)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(copiedBubbleScale ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: copiedBubbleScale)
            .onLongPressGesture(minimumDuration: 0.5) {
                copyToClipboard(content)
                // Trigger brief scale-down animation as visual feedback
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    copiedBubbleScale = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        copiedBubbleScale = false
                    }
                }
            }
    }

    private func chatStreamingBubble(content: String) -> some View {
        HStack {
            Text(LocalizedStringKey(content))
                .padding(12)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer(minLength: 60)
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        currentInput = ""

        // Start streaming
        isStreaming = true
        streamedAssistantContent = ""

        let model = selectedModel
        let transit = selectedTransit
        let category = categoryText.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            var placesContext: String? = nil

            // Pre-fetch Google Places if a category is specified
            if !category.isEmpty {
                do {
                    placesContext = try await service.searchNearbyPlaces(
                        category: category,
                        transitType: transit
                    )
                } catch {
                    // Graceful degradation: show alert but continue with chat
                    await MainActor.run {
                        errorMessage = "Ricerca luoghi fallita: \(error.localizedDescription)"
                        showError = true
                    }
                }
            }

            do {
                let stream = try await service.sendChatCompletion(
                    model: model,
                    messages: messages,
                    googlePlacesContext: placesContext,
                    autoSearchCategory: nil,
                    autoSearchTransit: nil
                )

                var accumulated = ""
                for try await chunk in stream {
                    accumulated += chunk
                    await MainActor.run {
                        streamedAssistantContent = accumulated
                    }
                }

                await MainActor.run {
                    if !accumulated.isEmpty {
                        messages.append(ChatMessage(role: .assistant, content: accumulated))
                    }
                    streamedAssistantContent = ""
                    isStreaming = false
                }
            } catch {
                await MainActor.run {
                    // Append whatever was streamed so far before the error
                    if !streamedAssistantContent.isEmpty {
                        messages.append(ChatMessage(role: .assistant, content: streamedAssistantContent))
                    }
                    streamedAssistantContent = ""
                    isStreaming = false
                    errorMessage = "Chat fallita: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    private func performAutoSearch() {
        let category = categoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.isEmpty, !isStreaming else { return }

        isStreaming = true
        streamedAssistantContent = ""
        // No user-visible message appended — the hidden prompt is assembled
        // inside OpenWebUIService using autoSearchCategory & autoSearchTransit

        let model = selectedModel
        let transit = selectedTransit
        let transitLabel = transit.rawValue  // "A piedi" / "In macchina"

        Task {
            var placesContext: String? = nil

            do {
                placesContext = try await service.searchNearbyPlaces(
                    category: category,
                    transitType: transit
                )
            } catch {
                await MainActor.run {
                    errorMessage = "Ricerca luoghi fallita: \(error.localizedDescription)"
                    showError = true
                }
            }

            do {
                let stream = try await service.sendChatCompletion(
                    model: model,
                    messages: messages,
                    googlePlacesContext: placesContext,
                    autoSearchCategory: category,
                    autoSearchTransit: transitLabel,
                    autoSearchLanguage: selectedLanguage
                )

                var accumulated = ""
                for try await chunk in stream {
                    accumulated += chunk
                    await MainActor.run {
                        streamedAssistantContent = accumulated
                    }
                }

                await MainActor.run {
                    if !accumulated.isEmpty {
                        messages.append(ChatMessage(role: .assistant, content: accumulated))
                    }
                    streamedAssistantContent = ""
                    isStreaming = false
                }
            } catch {
                await MainActor.run {
                    if !streamedAssistantContent.isEmpty {
                        messages.append(ChatMessage(role: .assistant, content: streamedAssistantContent))
                    }
                    streamedAssistantContent = ""
                    isStreaming = false
                    errorMessage = "Chat fallita: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation {
            proxy.scrollTo("bottomAnchor", anchor: .bottom)
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
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func resetChat() {
        guard !isStreaming else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            messages.removeAll()
            categoryText = ""
            streamedAssistantContent = ""
        }
    }
}

#Preview {
    NavigationStack {
        ChatView()
    }
}