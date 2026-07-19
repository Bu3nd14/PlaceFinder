//  MarkdownWebView.swift
//  PlaceFinder
//
//  Created on 18.07.26.
//

import SwiftUI
import WebKit

// MARK: - Self-Sizing WKWebView Subclass

/// A WKWebView subclass that reports its `scrollView.contentSize` as its
/// `intrinsicContentSize`, allowing SwiftUI to automatically size the view
/// to fit all rendered content without truncation.
final class SelfSizingWebView: WKWebView {
    /// True rendered height of the HTML content, measured via JavaScript.
    /// Zero means "not yet measured" — intrinsicContentSize will return
    /// `noIntrinsicMetric` to avoid collapsing or ballooning the bubble.
    var contentHeight: CGFloat = 0

    /// Keeps track of the last bounds to avoid invalidating intrinsic content
    /// size in a tight feedback loop during streaming. Only triggers a relayout
    /// when bounds genuinely change.
    private var lastBoundsSize: CGSize = .zero

    override var intrinsicContentSize: CGSize {
        guard contentHeight > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
        // Never constrain width — let the parent SwiftUI layout decide.
        // Only provide the measured content height.
        return CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastBoundsSize else { return }
        lastBoundsSize = bounds.size
        invalidateIntrinsicContentSize()
    }
}

// MARK: - MarkdownWebView

/// Renders a Markdown string using a WKWebView with native-looking CSS styling.
/// Supports tables, blockquotes, code blocks, headers, lists, hr, and all common
/// Markdown features that AttributedString does not handle.
struct MarkdownWebView: UIViewRepresentable {
    let markdown: String

    init(markdown: String) {
        self.markdown = markdown
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SelfSizingWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        let webView = SelfSizingWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = true
        webView.navigationDelegate = context.coordinator

        return webView
    }

    func updateUIView(_ webView: SelfSizingWebView, context: Context) {
        // Avoid redundant reloads during streaming — if the markdown string
        // hasn't changed, skip the expensive loadHTMLString + decidePolicyFor
        // + didFinish cycle that can cause bubble sizing glitches.
        guard markdown != context.coordinator.lastLoadedMarkdown else { return }
        context.coordinator.lastLoadedMarkdown = markdown

        // Reset measured height before the new load so the old contentHeight
        // doesn't balloon the bubble while the new HTML is still rendering.
        webView.contentHeight = 0
        webView.invalidateIntrinsicContentSize()

        let htmlBody = markdownToHTML(markdown)
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
        :root {
            color-scheme: light dark;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 16px;
            line-height: 1.5;
            color: #1c1c1e;
            background: transparent;
            -webkit-text-size-adjust: 100%;
            word-wrap: break-word;
        }
        @media (prefers-color-scheme: dark) {
            body { color: #e5e5ea; }
        }
        h1, h2, h3, h4, h5, h6 {
            margin-top: 0.85em;
            margin-bottom: 0.4em;
            font-weight: 600;
            line-height: 1.3;
        }
        h1 { font-size: 1.45em; border-bottom: 1px solid rgba(0,0,0,0.1); padding-bottom: 0.2em; }
        h2 { font-size: 1.3em; }
        h3 { font-size: 1.18em; }
        h4 { font-size: 1.08em; }
        h5, h6 { font-size: 1em; }
        p { margin-bottom: 0.7em; }
        strong { font-weight: 600; }
        em { font-style: italic; }
        a { color: #007aff; text-decoration: none; }
        a:visited { color: #007aff; }
        @media (prefers-color-scheme: dark) {
            a { color: #0a84ff; }
            a:visited { color: #0a84ff; }
            h1 { border-bottom-color: rgba(255,255,255,0.1); }
        }
        hr {
            border: none;
            border-top: 1px solid #c7c7cc;
            margin: 1em 0;
        }
        @media (prefers-color-scheme: dark) {
            hr { border-top-color: #48484a; }
        }
        blockquote {
            border-left: 3px solid #c7c7cc;
            padding-left: 12px;
            margin: 0.7em 0;
            color: #6e6e73;
        }
        @media (prefers-color-scheme: dark) {
            blockquote { border-left-color: #48484a; color: #8e8e93; }
        }
        ul, ol { margin: 0.5em 0 0.7em 0; padding-left: 1.5em; }
        li { margin-bottom: 0.2em; }
        code {
            font-family: "SF Mono", Menlo, monospace;
            font-size: 0.88em;
            background: #f4f4f5;
            padding: 0.15em 0.4em;
            border-radius: 4px;
        }
        @media (prefers-color-scheme: dark) {
            code { background: #2c2c2e; }
        }
        pre {
            background: #f4f4f5;
            padding: 12px;
            border-radius: 8px;
            margin: 0.7em 0;
            overflow-x: auto;
        }
        @media (prefers-color-scheme: dark) {
            pre { background: #2c2c2e; }
        }
        pre code {
            background: none;
            padding: 0;
            border-radius: 0;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 0.7em 0;
            font-size: 0.93em;
        }
        th, td {
            border: 1px solid #d1d1d6;
            padding: 7px 9px;
            text-align: left;
            vertical-align: top;
        }
        @media (prefers-color-scheme: dark) {
            th, td { border-color: #48484a; }
        }
        th {
            background: #f2f2f7;
            font-weight: 600;
        }
        @media (prefers-color-scheme: dark) {
            th { background: #3a3a3c; }
        }
        tr:nth-child(even) td {
            background: #f9f9fb;
        }
        @media (prefers-color-scheme: dark) {
            tr:nth-child(even) td { background: #2c2c2e; }
        }
        img { max-width: 100%; height: auto; }
        </style>
        </head>
        <body>\(htmlBody)</body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - Inline Markdown Processor (shared across methods)

    /// Renders inline Markdown patterns (bold, italic, code, links, images,
    /// strikethrough) to their HTML equivalents.
    private func processInlineMarkdown(_ line: String) -> String {
        var result = line

        // Inline code (single backtick) — process first to avoid interference
        result = result.replacingOccurrences(
            of: "`([^`]+)`",
            with: "<code>$1</code>",
            options: .regularExpression
        )

        // Bold **...**
        result = result.replacingOccurrences(
            of: "\\*\\*(.+?)\\*\\*",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )

        // Italic *...* (but not within words like don*t)
        result = result.replacingOccurrences(
            of: "(?<!\\*)\\*([^*\\n]+?)\\*(?!\\*)",
            with: "<em>$1</em>",
            options: .regularExpression
        )

        // Links [text](url)
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(([^)]+)\\)",
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )

        // Images ![alt](url)
        result = result.replacingOccurrences(
            of: "!\\[([^\\]]*)\\]\\(([^)]+)\\)",
            with: "<img alt=\"$1\" src=\"$2\">",
            options: .regularExpression
        )

        // Strikethrough ~~...~~
        result = result.replacingOccurrences(
            of: "~~(.+?)~~",
            with: "<s>$1</s>",
            options: .regularExpression
        )

        return result
    }

    // MARK: - Swift-Side Markdown to HTML Converter

    /// Converts a Markdown string into HTML, handling all common patterns:
    /// tables, code blocks (fenced + indented), inline code, headers, bold/italic,
    /// blockquotes, horizontal rules, links, and lists.
    private func markdownToHTML(_ input: String) -> String {
        let text = input
        var output = ""
        var pendingTableLines: [String] = []
        var inCodeBlock = false
        var codeBlockContent = ""

        func flushPendingTable() {
            guard !pendingTableLines.isEmpty else { return }
            output += renderHTMLTable(from: pendingTableLines)
            pendingTableLines = []
        }

        func flushCodeBlock() {
            let escaped = codeBlockContent
                .replacingOccurrences(of: "&", with: "&")
                .replacingOccurrences(of: "<", with: "<")
                .replacingOccurrences(of: ">", with: ">")
            output += "<pre><code>" + escaped + "</code></pre>"
            codeBlockContent = ""
        }

        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // --- Fenced Code Block ---
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if !inCodeBlock {
                    flushPendingTable()
                    inCodeBlock = true
                    codeBlockContent = ""
                } else {
                    flushCodeBlock()
                    inCodeBlock = false
                }
                i += 1
                continue
            }

            if inCodeBlock {
                if !codeBlockContent.isEmpty { codeBlockContent += "\n" }
                codeBlockContent += line
                i += 1
                continue
            }

            // --- Indented Code Block (4+ spaces) ---
            if line.hasPrefix("    ") && !line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushPendingTable()
                let escaped = line
                    .replacingOccurrences(of: "&", with: "&")
                    .replacingOccurrences(of: "<", with: "<")
                    .replacingOccurrences(of: ">", with: ">")
                output += "<pre><code>" + escaped + "</code></pre>"
                i += 1
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // --- Table Row ---
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                if trimmed.contains("---") || trimmed.contains(":--") || trimmed.contains("--:") {
                    // Separator row — skip
                    i += 1
                    continue
                }
                pendingTableLines.append(trimmed)
                i += 1
                continue
            } else {
                flushPendingTable()
            }

            // --- Empty Line ---
            if trimmed.isEmpty {
                output += "<br>"
                i += 1
                continue
            }

            // --- Horizontal Rule ---
            if trimmed == "---" || trimmed == "***" || trimmed == "___" || trimmed == "* * *" {
                output += "<hr>"
                i += 1
                continue
            }

            // --- Blockquote ---
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                var quoteContent = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                // Gather subsequent quote lines
                i += 1
                while i < lines.count {
                    let nextLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if nextLine.hasPrefix("> ") || nextLine == ">" {
                        quoteContent += "\n" + String(nextLine.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                        i += 1
                    } else {
                        break
                    }
                }
                output += "<blockquote><p>" + processInlineMarkdown(quoteContent).replacingOccurrences(of: "\n", with: "<br>") + "</p></blockquote>"
                continue
            }

            // --- Headers ---
            if trimmed.hasPrefix("###### ") {
                let content = String(trimmed.dropFirst(7))
                output += "<h6>" + processInlineMarkdown(content) + "</h6>"
                i += 1
                continue
            }
            if trimmed.hasPrefix("##### ") {
                let content = String(trimmed.dropFirst(6))
                output += "<h5>" + processInlineMarkdown(content) + "</h5>"
                i += 1
                continue
            }
            if trimmed.hasPrefix("#### ") {
                let content = String(trimmed.dropFirst(5))
                output += "<h4>" + processInlineMarkdown(content) + "</h4>"
                i += 1
                continue
            }
            if trimmed.hasPrefix("### ") {
                let content = String(trimmed.dropFirst(4))
                output += "<h3>" + processInlineMarkdown(content) + "</h3>"
                i += 1
                continue
            }
            if trimmed.hasPrefix("## ") {
                let content = String(trimmed.dropFirst(3))
                output += "<h2>" + processInlineMarkdown(content) + "</h2>"
                i += 1
                continue
            }
            if trimmed.hasPrefix("# ") {
                let content = String(trimmed.dropFirst(2))
                output += "<h1>" + processInlineMarkdown(content) + "</h1>"
                i += 1
                continue
            }

            // --- Unordered List ---
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                output += "<ul>"
                while i < lines.count {
                    let listLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if listLine.hasPrefix("- ") || listLine.hasPrefix("* ") || listLine.hasPrefix("+ ") {
                        let content = String(listLine.dropFirst(2))
                        output += "<li>" + processInlineMarkdown(content) + "</li>"
                        i += 1
                    } else {
                        break
                    }
                }
                output += "</ul>"
                continue
            }

            // --- Ordered List ---
            if trimmed.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                output += "<ol>"
                while i < lines.count {
                    let listLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if listLine.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                        let content = listLine.replacingOccurrences(of: #"^\d+\. "#, with: "", options: .regularExpression)
                        output += "<li>" + processInlineMarkdown(content) + "</li>"
                        i += 1
                    } else {
                        break
                    }
                }
                output += "</ol>"
                continue
            }

            // --- Regular Paragraph ---
            output += "<p>" + processInlineMarkdown(trimmed) + "</p>"
            i += 1
        }

        flushPendingTable()
        if inCodeBlock { flushCodeBlock() }

        return output
    }

    /// Converts accumulated |...| table rows into an HTML <table>.
    private func renderHTMLTable(from rows: [String]) -> String {
        guard !rows.isEmpty else { return "" }

        var html = "<table>"

        // First row is header
        if let headerRow = rows.first {
            let cells = parseTableRow(headerRow)
            html += "<thead><tr>"
            for cell in cells {
                html += "<th>" + processInlineMarkdown(cell) + "</th>"
            }
            html += "</tr></thead>"
        }

        // Remaining rows are body
        if rows.count > 1 {
            html += "<tbody>"
            for row in rows.dropFirst() {
                let cells = parseTableRow(row)
                html += "<tr>"
                for cell in cells {
                    html += "<td>" + processInlineMarkdown(cell) + "</td>"
                }
                html += "</tr>"
            }
            html += "</tbody>"
        }

        html += "</table>"
        return html
    }

    /// Splits a pipe-delimited table row into individual cell strings.
    private func parseTableRow(_ row: String) -> [String] {
        var trimmed = row
        if trimmed.hasPrefix("|") { trimmed = String(trimmed.dropFirst()) }
        if trimmed.hasSuffix("|") { trimmed = String(trimmed.dropLast()) }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        /// Tracks the last loaded markdown string to avoid redundant reloads
        /// during streaming that would trigger unnecessary JavaScript evaluation.
        var lastLoadedMarkdown: String?

        /// Intercepts link taps and opens them in the external browser (or Apple Maps)
        /// instead of navigating inside the bubble's WebView.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }
            // Open externally: maps, http, https, etc.
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Measure true content height via JavaScript — scrollView.contentSize
            // includes viewport insets and is unreliable for bubble sizing.
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak webView] result, _ in
                guard let webView = webView as? SelfSizingWebView,
                      let height = result as? CGFloat,
                      height > 0 else { return }
                webView.contentHeight = height
                DispatchQueue.main.async {
                    webView.invalidateIntrinsicContentSize()
                }
            }
        }
    }
}