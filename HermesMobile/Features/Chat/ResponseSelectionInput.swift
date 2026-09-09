import UIKit

/// Read-only UITextInput adapter. UIKit owns gestures, handles, and the edit menu;
/// the existing SwiftUI leaves continue to own rendering and link interactions.
final class ResponseSelectionInput: UIView, UITextInput, UITextInteractionDelegate, UIGestureRecognizerDelegate, UITextSelectionDisplayInteractionDelegate {
    weak var focusScope: ResponseSelectionFocusScope?
    var onWillBeginSelection: () -> Void = {}
    let leaves = NSHashTable<ResponseSelectionLeafView>.weakObjects()
    var leafOrder: [UUID] = []
    let selectionInteraction = UITextInteraction(for: .nonEditable)
    weak var inputDelegate: UITextInputDelegate?
    lazy var tokenizer: UITextInputTokenizer = UITextInputStringTokenizer(textInput: self)
    private var selection: UITextRange?
    var selectedTextRange: UITextRange? {
        get { selection }
        set {
            inputDelegate?.selectionWillChange(self)
            selection = newValue
            inputDelegate?.selectionDidChange(self)
            #if targetEnvironment(macCatalyst)
            pointerDisplay.isActivated = newValue?.isEmpty == false && isFirstResponder
            pointerDisplay.setNeedsSelectionUpdate()
            #endif
        }
    }
    var markedTextRange: UITextRange? { nil }
    var markedTextStyle: [NSAttributedString.Key: Any]?
    var beginningOfDocument: UITextPosition { ResponseTextPosition(0) }
    var endOfDocument: UITextPosition { ResponseTextPosition(document.text.length) }
    var hasText: Bool { document.text.length > 0 }
    var isEditable: Bool { false }
    var textInputView: UIView { subviews.first ?? self }
    override var canBecomeFirstResponder: Bool { true }
    // UITextInteraction promotes a UITextInput to an accessibility element.
    // This adapter is a container; expose the hosted text and controls instead.
    override var isAccessibilityElement: Bool {
        get { false }
        set {}
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        selectionInteraction.textInput = self
        selectionInteraction.delegate = self
        #if !targetEnvironment(macCatalyst)
        addInteraction(selectionInteraction)
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { selectedTextRange = nil }
    }

    #if targetEnvironment(macCatalyst)
    private lazy var pointerDisplay = UITextSelectionDisplayInteraction(textInput: self, delegate: self)
    private var pointerAnchor: UITextPosition?
    private lazy var pointerClick = UITapGestureRecognizer(target: self, action: #selector(clickSelection(_:)))
    private lazy var pointerWord = UITapGestureRecognizer(target: self, action: #selector(selectWord(_:)))
    private lazy var pointerSelection = UIPanGestureRecognizer(target: self, action: #selector(dragSelection(_:)))

    /// Catalyst's iPad interface supplies word selection, but not primary-button
    /// range dragging for a custom UITextInput. Wheel/trackpad scrolling and
    /// secondary clicks must continue to reach the transcript and its menus.
    func installPointerSelection(on view: UIView) {
        pointerSelection.allowedScrollTypesMask = []
        pointerWord.numberOfTapsRequired = 2
        pointerClick.require(toFail: pointerWord)
        pointerClick.cancelsTouchesInView = false
        for gesture in [pointerSelection, pointerClick, pointerWord] {
            gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
            gesture.delegate = self
            view.addGestureRecognizer(gesture)
        }
        view.addInteraction(UIContextMenuInteraction(delegate: self))
        view.addInteraction(pointerDisplay)
        pointerDisplay.isActivated = false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
        return gestureRecognizer !== pointerSelection || event.buttonMask == .primary
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pointerSelection else {
            return interactionShouldBegin(selectionInteraction, at: gestureRecognizer.location(in: self))
        }
        let location = pointerSelection.location(in: self)
        let translation = pointerSelection.translation(in: self)
        return interactionShouldBegin(selectionInteraction,
            at: CGPoint(x: location.x - translation.x, y: location.y - translation.y))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === pointerClick && otherGestureRecognizer !== pointerWord
            && !(otherGestureRecognizer is UIPanGestureRecognizer)
    }

    @objc private func clickSelection(_ tap: UITapGestureRecognizer) {
        becomeFirstResponder()
        selectedTextRange = nil
    }

    @objc private func selectWord(_ tap: UITapGestureRecognizer) {
        selectWord(at: tap.location(in: self))
    }

    func selectWord(at point: CGPoint) {
        guard let position = closestPosition(to: point) else { return }
        becomeFirstResponder()
        selectedTextRange = tokenizer.rangeEnclosingPosition(position, with: .word,
            inDirection: UITextDirection(rawValue: UITextStorageDirection.forward.rawValue))
            ?? characterRange(at: point)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                               configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let range = selectedTextRange, !range.isEmpty else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: String(localized: "Copy"), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.copy(nil) },
                UIAction(title: String(localized: "Select All")) { [weak self] _ in self?.selectAll(nil) }
            ])
        }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                               previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        selectionMenuPreview(interaction)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                               previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        selectionMenuPreview(interaction)
    }

    /// A selected-text menu must not snapshot and lift a multi-screen reply.
    private func selectionMenuPreview(_ interaction: UIContextMenuInteraction) -> UITargetedPreview {
        let anchor = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        anchor.backgroundColor = .clear
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.shadowPath = UIBezierPath()
        return UITargetedPreview(view: anchor, parameters: parameters,
            target: UIPreviewTarget(container: textInputView, center: interaction.location(in: textInputView)))
    }

    @objc private func dragSelection(_ pan: UIPanGestureRecognizer) {
        let point = pan.location(in: self)
        switch pan.state {
        case .began:
            let translation = pan.translation(in: self)
            beginPointerSelection(at: CGPoint(x: point.x - translation.x, y: point.y - translation.y))
            extendPointerSelection(to: point)
        case .changed, .ended:
            extendPointerSelection(to: point)
            if pan.state == .ended { pointerAnchor = nil }
        case .cancelled, .failed:
            pointerAnchor = nil
        default: break
        }
    }

    func beginPointerSelection(at point: CGPoint) {
        guard interactionShouldBegin(selectionInteraction, at: point) else { return }
        becomeFirstResponder()
        pointerDisplay.isActivated = true
        pointerAnchor = closestPosition(to: point)
        if let pointerAnchor { selectedTextRange = textRange(from: pointerAnchor, to: pointerAnchor) }
    }

    func extendPointerSelection(to point: CGPoint) {
        guard let pointerAnchor, let end = closestPosition(to: point) else { return }
        selectedTextRange = textRange(from: pointerAnchor, to: end)
    }
    #endif

    func interactionShouldBegin(_ interaction: UITextInteraction, at point: CGPoint) -> Bool {
        return document.glyphs.contains { $0.rect.contains(point) }
    }

    func interactionWillBegin(_ interaction: UITextInteraction) {
        #if targetEnvironment(macCatalyst)
        pointerDisplay.isActivated = false
        #endif
        becomeFirstResponder()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        #if targetEnvironment(macCatalyst)
        pointerDisplay.setNeedsSelectionUpdate()
        #endif
    }

    override func becomeFirstResponder() -> Bool {
        onWillBeginSelection()
        let became = super.becomeFirstResponder()
        if became { focusScope?.input = self }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            if focusScope?.input === self { focusScope?.input = nil }
            selectedTextRange = nil
            #if targetEnvironment(macCatalyst)
            pointerAnchor = nil
            pointerDisplay.isActivated = false
            #endif
        }
        return resigned
    }

    /// Geometry is read at interaction time so horizontal code scrolling and
    /// Dynamic Type never leave selection handles using stale screen positions.
    private var document: (text: NSString, glyphs: [ResponseSelectionGlyph]) {
        let indices = Dictionary(leafOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        let ordered = leaves.allObjects.filter { $0.window != nil && $0.isDescendant(of: self) }.sorted {
            if let leftIndex = indices[$0.id], let rightIndex = indices[$1.id] {
                return leftIndex < rightIndex
            }
            let left = $0.convert($0.bounds, to: self)
            let right = $1.convert($1.bounds, to: self)
            if abs(left.minY - right.minY) > 2 { return left.minY < right.minY }
            return $0.rightToLeft
                ? left.minX > right.minX : left.minX < right.minX
        }
        var text = ""
        var offset = 0
        var glyphs: [ResponseSelectionGlyph] = []
        for (index, leaf) in ordered.enumerated() {
            let length = leaf.text.utf16.count
            let nextColumn = index + 1 < ordered.count ? ordered[index + 1].tableColumn : nil
            let separator: String
            if leaf.tableColumn != nil {
                // Cell coordinates preserve rows even when cells wrap or scroll.
                separator = nextColumn.map { $0 == 0 ? "\n" : "\t" } ?? "\n\n"
            } else {
                separator = leaf.separator
            }
            text += leaf.text + separator
            var clip = bounds
            var ancestor = leaf.superview
            while let view = ancestor, view !== self {
                if view.clipsToBounds { clip = clip.intersection(view.convert(view.bounds, to: self)) }
                ancestor = view.superview
            }
            for glyph in leaf.geometry?.glyphs ?? [] where NSMaxRange(glyph.range) <= length {
                let rect = leaf.convert(glyph.rect, to: self).intersection(clip)
                guard !rect.isNull, !rect.isEmpty else { continue }
                glyphs.append(ResponseSelectionGlyph(
                    range: NSRange(location: offset + glyph.range.location, length: glyph.range.length),
                    rect: rect,
                    rightToLeft: glyph.rightToLeft
                ))
            }
            offset += length + separator.utf16.count
        }
        return (text as NSString, glyphs)
    }

    func text(in range: UITextRange) -> String? {
        guard let range = range as? ResponseTextRange else { return nil }
        let text = document.text
        guard range.range.location >= 0, NSMaxRange(range.range) <= text.length else { return nil }
        return text.substring(with: range.range)
    }

    func textRange(from: UITextPosition, to: UITextPosition) -> UITextRange? {
        guard let start = from as? ResponseTextPosition, let end = to as? ResponseTextPosition else { return nil }
        return ResponseTextRange(NSRange(location: min(start.offset, end.offset), length: abs(end.offset - start.offset)))
    }

    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let position = position as? ResponseTextPosition else { return nil }
        let value = position.offset + offset
        guard value >= 0, value <= document.text.length else { return nil }
        return ResponseTextPosition(value)
    }

    func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? {
        if direction == .up || direction == .down {
            let caret = caretRect(for: position)
            return closestPosition(to: CGPoint(x: caret.midX, y: caret.midY + CGFloat(direction == .up ? -offset : offset) * caret.height))
        }
        let rtl = baseWritingDirection(for: position, in: .forward) == .rightToLeft
        let forward = (direction == .right) != rtl
        return self.position(from: position, offset: forward ? offset : -offset)
    }

    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        let distance = offset(from: position, to: other)
        return distance == 0 ? .orderedSame : distance > 0 ? .orderedAscending : .orderedDescending
    }

    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        guard let start = from as? ResponseTextPosition, let end = toPosition as? ResponseTextPosition else { return 0 }
        return end.offset - start.offset
    }

    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        let rtl = baseWritingDirection(for: range.start, in: .forward) == .rightToLeft
        switch direction {
        case .left: return rtl ? range.end : range.start
        case .right: return rtl ? range.start : range.end
        case .up: return range.start
        case .down: return range.end
        @unknown default: return range.start
        }
    }

    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        if direction == .left || direction == .right, let position = position as? ResponseTextPosition {
            let rtl = baseWritingDirection(for: position, in: .forward) == .rightToLeft
            let forward = (direction == .right) != rtl
            let index = position.offset - (forward ? 0 : 1)
            let text = document.text
            guard index >= 0, index < text.length else { return nil }
            return ResponseTextRange(text.rangeOfComposedCharacterSequence(at: index))
        }
        guard let end = self.position(from: position, in: direction, offset: 1) else { return nil }
        return textRange(from: position, to: end)
    }

    func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        guard let position = position as? ResponseTextPosition else { return .natural }
        return nearestGlyph(to: position.offset, in: document.glyphs)?.rightToLeft == true ? .rightToLeft : .leftToRight
    }

    func firstRect(for range: UITextRange) -> CGRect { selectionRects(for: range).first?.rect ?? .zero }

    func caretRect(for position: UITextPosition) -> CGRect {
        guard let position = position as? ResponseTextPosition else { return .zero }
        let glyphs = document.glyphs
        guard let glyph = nearestGlyph(to: position.offset, in: glyphs) else { return .zero }
        let atEnd = position.offset >= NSMaxRange(glyph.range)
        let x = atEnd != glyph.rightToLeft ? glyph.rect.maxX : glyph.rect.minX
        return CGRect(x: x, y: glyph.rect.minY, width: 2, height: glyph.rect.height)
    }

    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        guard let range = range as? ResponseTextRange, !range.isEmpty else { return [] }
        // UIKit needs runs of selected text, not a separate highlight view for
        // every glyph in a long response. Keep bidi runs and media gaps separate.
        var runs: [ResponseSelectionGlyph] = []
        for glyph in document.glyphs where NSIntersectionRange(glyph.range, range.range).length > 0 {
            if let last = runs.last,
               last.rightToLeft == glyph.rightToLeft,
               abs(last.rect.minY - glyph.rect.minY) < 0.5,
               abs(last.rect.height - glyph.rect.height) < 0.5,
               (NSMaxRange(last.range) == glyph.range.location || NSMaxRange(glyph.range) == last.range.location),
               (abs(last.rect.maxX - glyph.rect.minX) < 1 || abs(glyph.rect.maxX - last.rect.minX) < 1) {
                runs[runs.count - 1] = ResponseSelectionGlyph(
                    range: NSUnionRange(last.range, glyph.range),
                    rect: last.rect.union(glyph.rect), rightToLeft: glyph.rightToLeft
                )
            } else {
                runs.append(glyph)
            }
        }
        let start = runs.map(\.range.location).min() ?? range.range.location
        let end = runs.map { NSMaxRange($0.range) - 1 }.max() ?? start
        return runs.map {
            ResponseSelectionRect($0, starts: NSLocationInRange(start, $0.range),
                                  ends: NSLocationInRange(end, $0.range))
        }
    }

    /// Paragraph separators have no drawn glyph. Anchor their caret to the
    /// nearest text boundary instead of jumping to the end of the response.
    private func nearestGlyph(to offset: Int, in glyphs: [ResponseSelectionGlyph]) -> ResponseSelectionGlyph? {
        if let exact = glyphs.first(where: { NSLocationInRange(offset, $0.range) }) { return exact }
        return glyphs.min {
            min(abs(offset - $0.range.location), abs(offset - NSMaxRange($0.range)))
                < min(abs(offset - $1.range.location), abs(offset - NSMaxRange($1.range)))
        }
    }

    func closestPosition(to point: CGPoint) -> UITextPosition? {
        closestPosition(to: point, within: ResponseTextRange(NSRange(location: 0, length: document.text.length)))
    }

    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        guard let range = range as? ResponseTextRange else { return nil }
        let candidates = document.glyphs.filter { NSIntersectionRange($0.range, range.range).length > 0 }
        let nearest = candidates.min { distance(point, to: $0.rect) < distance(point, to: $1.rect) }
        guard let nearest else { return range.start }
        let after = (point.x > nearest.rect.midX) != nearest.rightToLeft
        return ResponseTextPosition(min(NSMaxRange(range.range), max(range.range.location, after ? NSMaxRange(nearest.range) : nearest.range.location)))
    }

    func characterRange(at point: CGPoint) -> UITextRange? {
        guard let position = closestPosition(to: point) as? ResponseTextPosition else { return nil }
        let text = document.text
        guard text.length > 0 else { return nil }
        return ResponseTextRange(text.rangeOfComposedCharacterSequence(at: min(position.offset, text.length - 1)))
    }

    private func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy * 16
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copy(_:)) { return selectedTextRange?.isEmpty == false }
        if action == #selector(selectAll(_:)) { return hasText }
        return false
    }

    override func copy(_ sender: Any?) {
        guard let selectedTextRange, let text = text(in: selectedTextRange) else { return }
        UIPasteboard.general.string = text
    }

    override func selectAll(_ sender: Any?) {
        #if targetEnvironment(macCatalyst)
        pointerDisplay.isActivated = true
        #endif
        selectedTextRange = textRange(from: beginningOfDocument, to: endOfDocument)
    }

    func replace(_ range: UITextRange, withText text: String) {}
    func insertText(_ text: String) {}
    func deleteBackward() {}
    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {}
    func unmarkText() {}
    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}
}

#if targetEnvironment(macCatalyst)
extension ResponseSelectionInput: UIContextMenuInteractionDelegate {}
#endif
