import SwiftUI
import ChumCore

struct AIChatSettingsView: View {
    @AppStorage(AppSettings.aiProviderKey) private var aiProvider = "openai"
    @AppStorage(AppSettings.aiModelKey) private var aiModel = ""
    @State private var apiKey = APIKeyStore.read() ?? ""

    var body: some View {
        Form {
            Section {
                HotkeyRecorderView("Open AI Chat:", name: HotkeyManager.openAIChat)
            } header: {
                Text("Hotkey")
            } footer: {
                Text("Opens the Launcher on the AI Chat tool.")
            }

            Section {
                Picker("Provider", selection: $aiProvider) {
                    Text("OpenAI").tag("openai")
                    Text("Anthropic").tag("anthropic")
                    Text("Google").tag("google")
                    Text("Mistral").tag("mistral")
                    Text("OpenRouter").tag("openrouter")
                }
                TextField("Model", text: $aiModel, prompt: Text(ChatService.defaultModel(for: aiProvider)))
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key", text: $apiKey)
                    .privacySensitive()
            } header: {
                Text("API Access")
            } footer: {
                Text("Bring your own key — requests go straight from this Mac to the provider, nothing passes through any other server. The model field is free text; leave it empty to use the provider default shown in the placeholder. The key is stored in your Keychain.")
            }

            Section {
                Button(role: .destructive) {
                    ChatStore.shared.deleteAll()
                } label: {
                    Text("Delete All Discussions")
                }
                .disabled(ChatStore.shared.discussions.isEmpty)
            } header: {
                Text("Discussions")
            } footer: {
                Text("Chat discussions live in Application Support on this Mac.")
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            if apiKey.isEmpty {
                APIKeyStore.delete()
            } else {
                APIKeyStore.save(apiKey)
            }
        }
    }
}
