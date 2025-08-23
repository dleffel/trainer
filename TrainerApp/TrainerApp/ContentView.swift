import SwiftUI
import Foundation

// Minimal, iMessage-inspired chat with a persistent LLM-backed conversation.
// - Messages are persisted locally to a JSON file
// - API key and system prompt are stored in UserDefaults (simple, dev-friendly)
// - One file, self-contained starter you can extend as needed

struct ContentView: View {
    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var isSending: Bool = false
    @State private var showSettings: Bool = false
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "OPENAI_API_KEY") ?? ""
    @State private var systemPrompt: String = UserDefaults.standard.string(forKey: "SYSTEM_PROMPT") ?? "You are a concise, friendly assistant. Keep responses brief and helpful."
    @State private var errorMessage: String?

    private let persistence = ConversationPersistence()
    private let model = "gpt-5" // adjust if needed

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messagesList
                inputBar
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .onAppear {
            messages = (try? persistence.load()) ?? []
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                apiKey: $apiKey,
                systemPrompt: $systemPrompt,
                onClearChat: {
                    messages.removeAll()
                    try? persistence.clear()
                },
                onSave: {
                    UserDefaults.standard.set(apiKey, forKey: "OPENAI_API_KEY")
                    UserDefaults.standard.set(systemPrompt, forKey: "SYSTEM_PROMPT")
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    // MARK: - Views

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { msg in
                        bubble(for: msg)
                            .id(msg.id)
                    }
                    if isSending {
                        typingIndicator
                            .id("typing")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    if isSending {
                        proxy.scrollTo("typing", anchor: .bottom)
                    } else if let last = messages.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func bubble(for message: ChatMessage) -> some View {
        HStack {
            if message.role == .assistant {
                Bubble(text: message.content, isUser: false)
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                Bubble(text: message.content, isUser: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var typingIndicator: some View {
        HStack {
            ShimmerDot()
            ShimmerDot(delay: 0.2)
            ShimmerDot(delay: 0.4)
            Spacer()
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: 220, alignment: .leading)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message…", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .disabled(isSending)

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(canSend ? Color.blue : Color.gray)
            }
            .disabled(!canSend)
        }
        .padding(.all, 10)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    // MARK: - Actions

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !apiKey.isEmpty else {
            errorMessage = "Set your OpenAI API key in Settings."
            return
        }

        input = ""
        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)
        persist()

        isSending = true
        do {
            let assistantText = try await LLMClient.complete(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                history: messages
            )
            let assistantMsg = ChatMessage(role: .assistant, content: assistantText)
            messages.append(assistantMsg)
            persist()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSending = false
    }

    private func persist() {
        do { try persistence.save(messages) }
        catch { print("Persist error: \(error)") }
    }
}

// MARK: - Components

private struct Bubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(isUser ? .white : .primary)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(isUser ? Color.blue : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

private struct ShimmerDot: View {
    @State private var on = false
    var delay: Double = 0.0

    var body: some View {
        Circle()
            .fill(Color.secondary)
            .frame(width: 8, height: 8)
            .opacity(on ? 1.0 : 0.3)
            .animation(.easeInOut(duration: 0.8).repeatForever().delay(delay), value: on)
            .onAppear { on = true }
    }
}

private struct SettingsSheet: View {
    @Binding var apiKey: String
    @Binding var systemPrompt: String
    var onClearChat: () -> Void
    var onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI") {
                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("System Prompt") {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 100)
                        .font(.body.monospaced())
                }
                Section {
                    Button(role: .destructive) {
                        onClearChat()
                    } label: {
                        Label("Clear Conversation", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { onSave() }
                }
            }
        }
    }
}

// MARK: - Models & Persistence

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    let content: String
    let date: Date

    init(id: UUID = UUID(), role: Role, content: String, date: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.date = date
    }

    enum Role: String, Codable {
        case user, assistant
    }
}

private struct StoredMessage: Codable {
    let id: UUID
    let role: String
    let content: String
    let date: Date
}

private struct ConversationPersistence {
    private var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("conversation.json")
    }

    func load() throws -> [ChatMessage] {
        let data = try Data(contentsOf: url)
        let stored = try JSONDecoder().decode([StoredMessage].self, from: data)
        return stored.compactMap { s in
            guard let role = ChatMessage.Role(rawValue: s.role) else { return nil }
            return ChatMessage(id: s.id, role: role, content: s.content, date: s.date)
        }
    }

    func save(_ messages: [ChatMessage]) throws {
        let stored = messages.map { m in
            StoredMessage(id: m.id, role: m.role.rawValue, content: m.content, date: m.date)
        }
        let data = try JSONEncoder().encode(stored)
        try data.write(to: url, options: [.atomic])
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - LLM Client

enum LLMError: LocalizedError {
    case missingContent
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .missingContent: return "No content returned by the model."
        case .invalidResponse: return "Unexpected response from the model."
        case .httpError(let code): return "Network error: HTTP \(code)."
        }
    }
}

enum LLMClient {
    static func complete(
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [ChatMessage]
    ) async throws -> String {
        struct APIMessage: Codable { let role: String; let content: String }
        struct RequestBody: Codable { let model: String; let messages: [APIMessage] }
        struct ResponseBody: Codable {
            struct Choice: Codable {
                struct Msg: Codable { let role: String; let content: String }
                let index: Int
                let message: Msg
            }
            let choices: [Choice]
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var msgs: [APIMessage] = []
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            msgs.append(APIMessage(role: "system", content: systemPrompt))
        }
        for m in history {
            msgs.append(APIMessage(role: m.role == .user ? "user" : "assistant", content: m.content))
        }

        let body = try JSONEncoder().encode(RequestBody(model: model, messages: msgs))
        request.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LLMError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw LLMError.missingContent
        }
        return content
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
