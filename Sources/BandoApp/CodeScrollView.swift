import AppKit

/// Texto de código só leitura: NSTextView sem quebra de linha, com busca (⌘F),
/// e uma coluna de números de linha ao lado da área de rolagem. A coluna fica
/// fora da rolagem, então nunca cobre o começo das linhas. Só AppKit, para dar
/// para testar fora da interface SwiftUI.
final class CodeScrollView: NSView {
    let scrollView = NSScrollView()
    let textView: NSTextView
    private let gutter: LineGutter

    override init(frame: NSRect) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 4
        layout.addTextContainer(container)
        textView = NSTextView(frame: NSRect(origin: .zero, size: frame.size), textContainer: container)
        gutter = LineGutter(textView: textView)
        super.init(frame: frame)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = []
        scrollView.documentView = textView

        addSubview(gutter)
        addSubview(scrollView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(gutter, selector: #selector(LineGutter.redraw),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    required init?(coder: NSCoder) { fatalError("não usado") }

    override func layout() {
        super.layout()
        let w = gutter.width
        gutter.frame = NSRect(x: 0, y: 0, width: w, height: bounds.height)
        scrollView.frame = NSRect(x: w, y: 0, width: max(bounds.width - w, 0), height: bounds.height)
    }

    /// Troca o texto (mantendo a rolagem quando é o mesmo arquivo relido) e as cores.
    func show(text: String, font: NSFont, foreground: NSColor, background: NSColor, selection: NSColor?) {
        if textView.string != text || textView.font != font {
            let keep = textView.string.isEmpty ? NSPoint.zero : scrollView.contentView.bounds.origin
            textView.textStorage?.setAttributedString(
                NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: foreground]))
            textView.font = font
            textView.sizeToFit()
            scrollView.contentView.scroll(to: keep)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            var lines = 1
            for c in text.utf8 where c == 10 { lines += 1 }
            if text.hasSuffix("\n") { lines -= 1 }
            gutter.lineCount = max(lines, 1)
        }
        textView.textColor = foreground
        if let selection { textView.selectedTextAttributes = [.backgroundColor: selection] }
        gutter.font = NSFont.monospacedDigitSystemFont(ofSize: max(font.pointSize - 1, 8), weight: .regular)
        gutter.background = background
        needsLayout = true
        gutter.needsDisplay = true
    }
}

/// Coluna com os números das linhas visíveis.
final class LineGutter: NSView {
    var font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    var background: NSColor = .textBackgroundColor
    var lineCount = 1
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("não usado") }

    override var isFlipped: Bool { true }

    /// Largura pela quantidade de dígitos do total de linhas (mínimo 2).
    var width: CGFloat {
        let digit = ("8" as NSString).size(withAttributes: [.font: font]).width
        return ceil(CGFloat(max(String(lineCount).count, 2)) * digit + 18)
    }

    @objc func redraw() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        bounds.fill()
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let text = tv.string as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        // Onde a origem do texto cai nesta coluna (a rolagem vertical entra aqui).
        let offset = convert(NSPoint.zero, from: tv).y + tv.textContainerInset.height
        guard text.length > 0 else {
            label("1", y: offset, height: font.pointSize + 4, attrs: attrs)
            return
        }
        let visible = tv.visibleRect
        let glyphs = lm.glyphRange(forBoundingRect: visible, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = 1
        text.enumerateSubstrings(in: NSRange(location: 0, length: chars.location),
                                 options: [.byLines, .substringNotRequired]) { _, _, _, _ in line += 1 }
        var index = chars.location
        while index < NSMaxRange(chars) {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let r = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: index), effectiveRange: nil)
            label("\(line)", y: r.minY + offset, height: r.height, attrs: attrs)
            index = NSMaxRange(lineRange)
            line += 1
        }
    }

    private func label(_ s: String, y: CGFloat, height: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        let str = s as NSString
        let size = str.size(withAttributes: attrs)
        str.draw(at: NSPoint(x: bounds.width - size.width - 8, y: y + (height - size.height) / 2), withAttributes: attrs)
    }
}
