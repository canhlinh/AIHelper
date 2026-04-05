//
//  MarkdownRenderer.swift
//  AIHelper
//

import SwiftUI
import AppKit

struct MarkdownContentView: View {
    let text: String
    var fontSize: CGFloat = 15
    var color: Color = .white
    var fontDesign: Font.Design = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parseSegments(), id: \.id) { segment in
                if segment.isCode {
                    CodeBlockView(code: segment.content, language: segment.language)
                } else {
                    Text(LocalizedStringKey(segment.content))
                        .font(.system(size: fontSize, design: fontDesign))
                        .foregroundStyle(color)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    private struct Segment: Identifiable {
        let id = UUID()
        let content: String
        let isCode: Bool
        let language: String?
    }
    
    private func parseSegments() -> [Segment] {
        var segments: [Segment] = []
        let pattern = "```([a-zA-Z0-9]*)\\n([\\s\\S]*?)\\n```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [Segment(content: text, isCode: false, language: nil)]
        }
        
        let nsString = text as NSString
        var lastOffset = 0
        
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            // Text before code block
            let beforeRange = NSRange(location: lastOffset, length: match.range.location - lastOffset)
            if beforeRange.length > 0 {
                let content = nsString.substring(with: beforeRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty {
                    segments.append(Segment(content: content, isCode: false, language: nil))
                }
            }
            
            // Code block
            let langRange = match.range(at: 1)
            let codeRange = match.range(at: 2)
            
            let language = langRange.length > 0 ? nsString.substring(with: langRange) : nil
            let code = nsString.substring(with: codeRange)
            
            segments.append(Segment(content: code, isCode: true, language: language))
            
            lastOffset = match.range.location + match.range.length
        }
        
        // Remaining text
        if lastOffset < nsString.length {
            let remainingContent = nsString.substring(from: lastOffset).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainingContent.isEmpty {
                segments.append(Segment(content: remainingContent, isCode: false, language: nil))
            }
        }
        
        if segments.isEmpty && !text.isEmpty {
            segments.append(Segment(content: text, isCode: false, language: nil))
        }
        
        return segments
    }
}

struct CodeBlockView: View {
    let code: String
    let language: String?
    
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if let language = language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
                
                Spacer()
                
                Button {
                    copyToClipboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied" : "Copy")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isCopied ? .green : .white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05))
            
            // Code
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(code, forType: .string)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        MarkdownContentView(text: "Here is some **bold** text and a code block:\n\n```swift\nprint(\"Hello World\")\nlet x = 10\n```\nAnd more text.")
            .padding()
            .background(Color.gray.opacity(0.2))
    }
    .frame(width: 400)
}
