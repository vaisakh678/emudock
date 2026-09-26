import AppKit

/// The About panel and links to the project on GitHub.
enum About {
    static let repositoryURL = URL(string: "https://github.com/vaisakh678/emudock")!
    static let issuesURL = repositoryURL.appending(path: "issues")

    /// The standard About panel (icon, name, version, copyright) with a tagline and GitHub link.
    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]

        let credits = NSMutableAttributedString(string: "Android emulators, zero setup.\n\n", attributes: body)
        var link = body
        link[.link] = repositoryURL
        credits.append(NSAttributedString(string: "github.com/vaisakh678/emudock", attributes: link))

        NSApplication.shared.activate()
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    static func openRepository() {
        NSWorkspace.shared.open(repositoryURL)
    }

    static func openIssues() {
        NSWorkspace.shared.open(issuesURL)
    }
}
