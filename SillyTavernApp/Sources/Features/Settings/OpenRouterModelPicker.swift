import SwiftUI

// MARK: - OpenRouter Model Picker

struct OpenRouterModelPicker: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var models: [OpenRouterModel] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var searchText = ""

    var filteredModels: [OpenRouterModel] {
        if searchText.isEmpty {
            return models
        }
        return models.filter {
            $0.id.localizedCaseInsensitiveContains(searchText) ||
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading models...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = error {
                    errorView(error)
                } else if models.isEmpty {
                    emptyView
                } else {
                    modelList
                }
            }
            .navigationTitle("Select Model")
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 400)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await fetchModels() }
                    }
                    .disabled(isLoading)
                }
            }
            .searchable(text: $searchText, prompt: "Search models...")
        }
        .task {
            await fetchModels()
        }
    }

    // MARK: - Model List

    private var modelList: some View {
        List {
            // Popular models section
            if searchText.isEmpty {
                Section("Popular") {
                    ForEach(popularModels) { model in
                        modelRow(model)
                    }
                }
            }

            // All models section
            Section(searchText.isEmpty ? "All Models" : "Results") {
                ForEach(filteredModels) { model in
                    modelRow(model)
                }
            }
        }
        .listStyle(.inset)
    }

    private func modelRow(_ model: OpenRouterModel) -> some View {
        Button {
            appState.settings.model = model.id
            // Use exact context from OpenRouter API (more accurate than static lookup)
            if model.contextLength > 0 && appState.settings.autoContextSize {
                appState.settings.maxContextTokens = model.contextLength
            }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                // Model icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor(for: model.id).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: iconName(for: model.id))
                        .font(.title3)
                        .foregroundStyle(iconColor(for: model.id))
                }

                // Model info
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        if model.contextLength > 0 {
                            Label("\(model.contextLength / 1024)K", systemImage: "text.alignleft")
                        }
                        if let pricing = model.pricing {
                            Label(pricing, systemImage: "dollarsign.circle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Selected indicator
                if appState.settings.model == model.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - States

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Error Loading Models", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await fetchModels() }
            }
            .buttonStyle(.bordered)
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Models", systemImage: "cpu")
        } description: {
            Text("Enter your OpenRouter API key in settings to browse models")
        }
    }

    // MARK: - Helpers

    private var popularModels: [OpenRouterModel] {
        let popularIds = [
            "anthropic/claude-sonnet-4",
            "anthropic/claude-3.5-sonnet",
            "openai/gpt-4o",
            "openai/gpt-4o-mini",
            "google/gemini-2.0-flash-exp:free",
            "meta-llama/llama-3.3-70b-instruct",
            "deepseek/deepseek-chat"
        ]
        return popularIds.compactMap { id in
            models.first { $0.id == id }
        }
    }

    private func iconName(for modelId: String) -> String {
        let id = modelId.lowercased()
        if id.contains("claude") { return "brain.head.profile" }
        if id.contains("gpt") || id.contains("openai") { return "sparkles" }
        if id.contains("gemini") || id.contains("google") { return "diamond" }
        if id.contains("llama") || id.contains("meta") { return "hare" }
        if id.contains("mistral") { return "wind" }
        if id.contains("deepseek") { return "magnifyingglass" }
        if id.contains("qwen") { return "character.book.closed" }
        return "cpu"
    }

    private func iconColor(for modelId: String) -> Color {
        let id = modelId.lowercased()
        if id.contains("claude") { return .orange }
        if id.contains("gpt") || id.contains("openai") { return .green }
        if id.contains("gemini") || id.contains("google") { return .blue }
        if id.contains("llama") || id.contains("meta") { return .purple }
        if id.contains("mistral") { return .cyan }
        if id.contains("deepseek") { return .indigo }
        return .secondary
    }

    // MARK: - API

    private func fetchModels() async {
        guard !appState.settings.apiKey.isEmpty else {
            error = "No API key configured"
            return
        }

        isLoading = true
        error = nil

        do {
            let url = URL(string: "https://openrouter.ai/api/v1/models")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(appState.settings.apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 401 {
                error = "Invalid API key"
                isLoading = false
                return
            }

            if httpResponse.statusCode >= 400 {
                error = "Server error: \(httpResponse.statusCode)"
                isLoading = false
                return
            }

            let modelsResponse = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)

            // Sort by popularity/name
            models = modelsResponse.data
                .sorted { ($0.name) < ($1.name) }

            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Response Types

private struct OpenRouterModelsResponse: Decodable {
    let data: [OpenRouterModel]
}

struct OpenRouterModel: Identifiable, Decodable {
    let id: String
    let name: String
    let contextLength: Int
    let pricingInfo: ModelPricing?

    var pricing: String? {
        guard let pricingInfo = pricingInfo else { return nil }
        let promptPrice = (Double(pricingInfo.prompt) ?? 0) * 1_000_000
        let completionPrice = (Double(pricingInfo.completion) ?? 0) * 1_000_000
        if promptPrice == 0 && completionPrice == 0 {
            return "Free"
        }
        return String(format: "$%.2f/$%.2f per 1M", promptPrice, completionPrice)
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case contextLength = "context_length"
        case pricingInfo = "pricing"
    }

    struct ModelPricing: Decodable {
        let prompt: String
        let completion: String
    }
}

// MARK: - Preview

#Preview {
    OpenRouterModelPicker()
        .environment(AppState())
}
