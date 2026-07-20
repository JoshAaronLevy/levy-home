import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard
            let content = request.content.mutableCopy() as? UNMutableNotificationContent,
            let levyHome = request.content.userInfo["levyHome"] as? [String: Any],
            let imageURLText = levyHome["imageURL"] as? String,
            let imageURL = URL(string: imageURLText)
        else {
            contentHandler(request.content)
            return
        }

        bestAttemptContent = content
        URLSession.shared.downloadTask(with: imageURL) { [weak self] temporaryURL, response, _ in
            defer { contentHandler(self?.bestAttemptContent ?? request.content) }
            guard
                let self,
                let temporaryURL,
                let mimeType = response?.mimeType,
                mimeType.hasPrefix("image/")
            else { return }

            let fileExtension: String
            switch mimeType {
            case "image/png": fileExtension = "png"
            case "image/heic", "image/heif": fileExtension = "heic"
            default: fileExtension = "jpg"
            }
            let destination = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("doorbell-\(UUID().uuidString).\(fileExtension)")
            do {
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                let attachment = try UNNotificationAttachment(identifier: "doorbell-image", url: destination)
                self.bestAttemptContent?.attachments = [attachment]
            } catch {
                // Preserve the text notification when downloading or attaching fails.
            }
        }.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
