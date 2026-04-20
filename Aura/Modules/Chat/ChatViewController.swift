//
//  ChatViewController.swift
//  Aura
//
//  Created by Chance Q on 11/17/25.
//  Member B - Chat flow
//

import UIKit

final class ChatViewController: UIViewController {
    private let chatView = ChatView()
    private var messages: [ChatMessage] = []
    
    private let repository = ChatRepository.shared
    private let chatService = ChatService.shared
    
    // MARK: - Lifecycle
    override func loadView() {
        view = chatView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AI Chat"
        view.backgroundColor = UIColor.systemBackground

        setupNavigation()

        chatView.tableView.dataSource = self
        chatView.tableView.delegate = self
        chatView.tableView.register(ChatMessageCell.self, forCellReuseIdentifier: "ChatMessageCell")
        chatView.inputTextView.delegate = self
        chatView.sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        // Keyboard handling
        setupKeyboardObservers()
        addDismissKeyboardGesture()

        loadHistory()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Actions
    @objc private func sendTapped() {
        let text = chatView.inputTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        chatView.inputTextView.text = ""
        chatView.updatePlaceholderVisibility()
        
        let userMessage = ChatMessage(sender: .user, text: text)
        appendAndPersist(userMessage)
        
        chatService.reply(to: text) { [weak self] response in
            self?.appendAndPersist(response)
        }
    }
    
    // MARK: - Data
    private func loadHistory() {
        guard let uid = AuthService.shared.currentUserUID else {
            seedGreeting(persist: false)
            return
        }
        repository.fetchRecent(uid: uid) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let history):
                    if history.isEmpty {
                        self.seedGreeting(persist: true)
                    } else {
                        self.messages = history
                        self.chatView.tableView.reloadData()
                        self.scrollToBottom()
                    }
                case .failure:
                    self.seedGreeting(persist: false)
                }
            }
        }
    }
    
    private func appendAndPersist(_ message: ChatMessage) {
        messages.append(message)
        chatView.tableView.reloadData()
        scrollToBottom()
        
        guard let uid = AuthService.shared.currentUserUID else { return }
        repository.addMessage(uid: uid, message: message) { result in
            if case let .failure(error) = result {
                print("⚠️ Failed to write chat message: \(error.localizedDescription)")
            }
        }
    }
    
    private func seedGreeting(persist: Bool) {
        let greeting = defaultGreeting()
        messages = [greeting]
        chatView.tableView.reloadData()
        scrollToBottom()
        if persist, let uid = AuthService.shared.currentUserUID {
            repository.addMessage(uid: uid, message: greeting) { result in
                if case let .failure(error) = result {
                    print("⚠️ Failed to persist greeting: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func defaultGreeting() -> ChatMessage {
        ChatMessage(sender: .ai, text: "Hello! How are you today?")
    }
    
    private func scrollToBottom() {
        guard !messages.isEmpty else { return }
        let index = IndexPath(row: messages.count - 1, section: 0)
        chatView.tableView.scrollToRow(at: index, at: .bottom, animated: true)
    }
}

// MARK: - Navigation
private extension ChatViewController {
    func setupNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Get Help",
            style: .plain,
            target: self,
            action: #selector(openResourcesTapped)
        )
    }

    @objc func openResourcesTapped() {
        // Emit deep link style event so Home can route
        EventBus.shared.emit(.openResources)
    }
}

// MARK: - TableView
extension ChatViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatMessageCell", for: indexPath) as! ChatMessageCell
        cell.configure(with: messages[indexPath.row])
        return cell
    }
}

// MARK: - TextView
extension ChatViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        chatView.updatePlaceholderVisibility()
    }
}

// MARK: - Keyboard
private extension ChatViewController {
    func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let frame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }

        let height = frame.height - view.safeAreaInsets.bottom
        UIView.animate(withDuration: duration,
                       delay: 0,
                       options: UIView.AnimationOptions(rawValue: curveValue << 16),
                       animations: {
            self.chatView.bottomInset = height + 8
            self.chatView.layoutIfNeeded()
            self.scrollToBottom()
        })
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }

        UIView.animate(withDuration: duration,
                       delay: 0,
                       options: UIView.AnimationOptions(rawValue: curveValue << 16),
                       animations: {
            self.chatView.bottomInset = 0
            self.chatView.layoutIfNeeded()
        })
    }
}

// MARK: - Chat Cell
private final class ChatMessageCell: UITableViewCell {
    private let bubbleView = UIView()
    private let messageLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        
        contentView.addSubview(bubbleView)
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.layer.cornerRadius = 18
        bubbleView.layer.borderWidth = 1.2
        
        bubbleView.addSubview(messageLabel)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.numberOfLines = 0
        messageLabel.font = UIFont.systemFont(ofSize: 15)
        
        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 14),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -14)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with message: ChatMessage) {
        messageLabel.text = message.text
        
        // Remove old constraints to realign bubble for sender
        NSLayoutConstraint.deactivate(contentView.constraints.filter { constraint in
            constraint.firstItem === bubbleView || constraint.secondItem === bubbleView
        })
        
        let isUser = message.sender == .user
        bubbleView.layer.borderColor = UIColor.systemPurple.withAlphaComponent(0.6).cgColor
        bubbleView.backgroundColor = isUser
            ? UIColor.systemPurple.withAlphaComponent(0.15)
            : UIColor.systemGray6
        messageLabel.textColor = .label
        
        let leadingAnchor = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24)
        let trailingAnchor = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24)
        let horizontalAnchor: NSLayoutConstraint
        
        if isUser {
            horizontalAnchor = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        } else {
            horizontalAnchor = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        }
        
        NSLayoutConstraint.activate([
            leadingAnchor,
            trailingAnchor,
            horizontalAnchor,
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
}
