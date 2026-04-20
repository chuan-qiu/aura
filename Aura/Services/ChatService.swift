//
//  ChatService.swift
//  Aura
//
//  Created by Chance Q on 11/17/25.
//

import Foundation

final class ChatService {
    static let shared = ChatService()
    private init() {}

    private let systemPrompt = """
        You are Aura, a warm and supportive mental wellness companion. \
        Respond with empathy and care. Keep replies concise (2-3 sentences). \
        Never diagnose or replace professional help — encourage it when appropriate.
        """

    private var history: [[String: String]] = []

    func reply(to userMessage: String, completion: @escaping (ChatMessage) -> Void) {
        guard let url = URL(string: APIConfigs.groqURL) else { return }

        history.append(["role": "user", "content": userMessage])

        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        messages.append(contentsOf: history)

        let body: [String: Any] = [
            "model": APIConfigs.groqModel,
            "messages": messages,
            "max_tokens": 150,
            "temperature": 0.7
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(APIConfigs.groqToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            let fallback = ChatMessage(sender: .ai, text: "I'm having trouble responding right now. Please try again.")

            guard let data, error == nil else {
                DispatchQueue.main.async { completion(fallback) }
                return
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let message = choices.first?["message"] as? [String: Any],
                let text = message["content"] as? String, !text.isEmpty
            else {
                print("⚠️ Groq parse error: \(String(data: data, encoding: .utf8) ?? "nil")")
                DispatchQueue.main.async { completion(fallback) }
                return
            }

            self.history.append(["role": "assistant", "content": text])

            DispatchQueue.main.async {
                completion(ChatMessage(sender: .ai, text: text))
            }
        }.resume()
    }

    func clearHistory() {
        history = []
    }
}
