import SwiftUI
import XCTest
@testable import HermesMobile

@MainActor
final class ResponseSelectionTests: XCTestCase {
    func testSwiftUIResponseBoundaryRegistersItsHostedText() async throws {
        let controller = UIHostingController(rootView: ResponseTextSelection(identity: "response") {
            Text("A completed response").responseSelectableText("A completed response")
        })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let rendered = expectation(description: "SwiftUI boundary rendered")
        DispatchQueue.main.async {
            controller.view.layoutIfNeeded()
            _ = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            rendered.fulfill()
        }
        await fulfillment(of: [rendered], timeout: 5)
        func selectionInput(in view: UIView) -> ResponseSelectionInput? {
            if let input = view as? ResponseSelectionInput { return input }
            return view.subviews.lazy.compactMap { selectionInput(in: $0) }.first
        }
        let input = try XCTUnwrap(selectionInput(in: controller.view))
        input.selectAll(nil)
        let range = try XCTUnwrap(input.selectedTextRange)
        XCTAssertEqual(input.text(in: range), "A completed response\n")
        let rect = try XCTUnwrap(input.selectionRects(for: range).first).rect
        XCTAssertTrue(input.interactionShouldBegin(UITextInteraction(for: .nonEditable), at: CGPoint(x: rect.midX, y: rect.midY)))
        XCTAssertFalse(input.isAccessibilityElement)
        XCTAssertFalse(try XCTUnwrap(input.accessibilityElements).isEmpty)
    }

    func testRealMarkdownRegistersHeadingsListsCodeAndTableButNotEquations() async throws {
        let markdown = """
        # Heading

        First **paragraph** with a [link](https://example.com).

        - List entry
        - Another entry

        ```
        let value = 1
        ```

        $$x^2$$

        | Column | Value |
        | --- | --- |
        | Row | Cell |
        """
        let controller = ResponseSelectionController()
        controller.loadViewIfNeeded()
        controller.host.rootView = AnyView(MarkdownRenderer(content: markdown)
            .responseSelectionDocument(controller.scope))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 900))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let rendered = expectation(description: "Markdown laid out and drawn")
        DispatchQueue.main.async {
            controller.view.layoutIfNeeded()
            _ = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            rendered.fulfill()
        }
        await fulfillment(of: [rendered], timeout: 5)
        controller.input.selectAll(nil)
        let text = try XCTUnwrap(controller.input.text(in: XCTUnwrap(controller.input.selectedTextRange)))
        for expected in ["Heading", "First paragraph with a link.", "List entry", "Another entry", "let value = 1", "Column", "Value", "Row", "Cell"] {
            XCTAssertTrue(text.contains(expected), "Missing \(expected) in \(text)")
        }
        XCTAssertTrue(text.contains("Column\tValue\nRow\tCell\n\n"), text)
        XCTAssertFalse(text.contains("x^2"))
        XCTAssertFalse(text.contains("x²"))
        XCTAssertFalse(text.contains("Copy code"))
        XCTAssertFalse(controller.input.selectionRects(for: try XCTUnwrap(controller.input.selectedTextRange)).isEmpty)
    }

    func testSelectionSpansTextLeavesAndExcludesOtherViewsAndResponses() async throws {
        let controller = ResponseSelectionController()
        controller.loadViewIfNeeded()
        controller.host.rootView = AnyView(VStack(alignment: .leading) {
            Text("First paragraph").responseSelectableText("First paragraph", separator: "\n\n")
            Text("An equation image").accessibilityLabel("Equation")
            Text("let value = 1").font(.system(.body, design: .monospaced))
                .responseSelectableText("let value = 1")
        }.responseSelectionDocument(controller.scope))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let rendered = expectation(description: "Hosted response laid out and drawn")
        DispatchQueue.main.async {
            controller.view.layoutIfNeeded()
            _ = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            rendered.fulfill()
        }
        await fulfillment(of: [rendered], timeout: 5)

        let input = controller.input
        input.selectAll(nil)
        let selection = try XCTUnwrap(input.selectedTextRange)
        XCTAssertEqual(input.text(in: selection), "First paragraph\n\nlet value = 1\n")
        XCTAssertFalse(input.selectionRects(for: selection).isEmpty)
        XCTAssertTrue(input.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))

        let another = ResponseSelectionInput()
        XCTAssertFalse(another.hasText)
        XCTAssertNil(another.selectedTextRange)
    }

    func testRenderedGlyphOffsetsMatchUTF16IncludingEmojiAndCombiningCharacters() async throws {
        let text = "A 👩🏽‍💻 é שלום"
        let controller = ResponseSelectionController()
        controller.loadViewIfNeeded()
        controller.host.rootView = AnyView(Text(verbatim: text).responseSelectableText(text)
            .responseSelectionDocument(controller.scope))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let rendered = expectation(description: "Unicode text rendered")
        DispatchQueue.main.async {
            controller.view.layoutIfNeeded()
            _ = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            rendered.fulfill()
        }
        await fulfillment(of: [rendered], timeout: 5)
        let leaf = try XCTUnwrap(controller.input.leaves.allObjects.first)
        let glyphs = try XCTUnwrap(leaf.geometry).glyphs
        XCTAssertFalse(glyphs.isEmpty)
        XCTAssertEqual(glyphs.map { NSMaxRange($0.range) }.max(), text.utf16.count)
        XCTAssertTrue(glyphs.contains(where: \.rightToLeft))
        let emoji = try XCTUnwrap(controller.input.characterRange(byExtending: ResponseTextPosition(2), in: .right))
        XCTAssertEqual(controller.input.text(in: emoji), "👩🏽‍💻")
    }
    func testSelectionFocusHandoffIsScopedToTheChatAndClearsOnResign() async throws {
        let scope = ResponseSelectionFocusScope()
        let otherChat = ResponseSelectionFocusScope()
        var handedOff = false
        let (window, host) = await renderedHost(ResponseTextSelection(identity: "focus") {
            Text("Selectable response").responseSelectableText("Selectable response")
        }
        .environment(\.responseSelectionFocusScope, scope)
        .environment(\.responseSelectionWillBegin, { handedOff = true }))
        defer { window.isHidden = true }
        let input = try XCTUnwrap(selectionInputs(in: host.view).first)
        XCTAssertTrue(input.becomeFirstResponder())
        XCTAssertTrue(handedOff)
        XCTAssertTrue(scope.isActive)
        XCTAssertFalse(otherChat.isActive)
        input.selectAll(nil)
        XCTAssertTrue(input.resignFirstResponder())
        XCTAssertFalse(scope.isActive)
        XCTAssertNil(scope.input)
        XCTAssertNil(input.selectedTextRange)
    }

    func testGlyphEndpointsExpandWholeUnicodeCharacters() {
        for text in ["A 👩🏽‍💻", "A e\u{301}", "A 🇺🇸"] {
            let source = ResponseSelectionText(source: text)
            let expected = (text as NSString).rangeOfComposedCharacterSequence(at: 2)
            XCTAssertEqual(source.selectableRange(for: NSRange(location: 2, length: 1)), expected)
            XCTAssertEqual(NSMaxRange(expected), text.utf16.count)
        }
        let source = ResponseSelectionText(source: "a\u{fffc}b", excludedOffsets: [1])
        XCTAssertNil(source.selectableRange(for: NSRange(location: 1, length: 1)))
        XCTAssertEqual(source.selectableRange(for: NSRange(location: 2, length: 1)), NSRange(location: 1, length: 1))
        XCTAssertEqual(source.selectableText, "ab")
    }

    func testUserBubbleRegistersTextAndStreamingResponseDoesNot() async throws {
        let user = MessageBubbleView(message: ChatMessage(role: "user", content: "First line\nSecond 👩🏽‍💻 line", timestamp: 1, messageId: "user"))
        let (window, host) = await renderedHost(user)
        defer { window.isHidden = true }
        let input = try XCTUnwrap(selectionInputs(in: host.view).first)
        input.selectAll(nil)
        XCTAssertEqual(input.text(in: try XCTUnwrap(input.selectedTextRange)), "First line\nSecond 👩🏽‍💻 line")

        let (streamWindow, streamHost) = await renderedHost(MessageBubbleView(
            message: ChatMessage(role: "assistant", content: "Still streaming", timestamp: 2, messageId: "stream"), isStreaming: true))
        defer { streamWindow.isHidden = true }
        XCTAssertTrue(selectionInputs(in: streamHost.view).isEmpty)
    }

    func testInlineChipsDoNotShiftSurroundingSelectableGlyphs() async throws {
        let text = "Before /skill after 👩🏽‍💻"
        let token = ComposerChipToken(range: (text as NSString).range(of: "/skill"),
            source: "/skill", label: "Skill", kind: .skill)
        let source = ComposerChipTextLine.selectionSource(text, tokens: [token])
        let selected = ResponseSelectionText(source: source.text, excludedOffsets: source.excludedOffsets).selectableText
        let style = ComposerChipTextStyle(colorScheme: .light, contrast: .standard,
            layoutDirection: .leftToRight, dynamicTypeSize: .large)
        let (window, host) = await renderedHost(ResponseTextSelection(identity: "chips") {
            ComposerChipTextLine.text(text, tokens: [token], style: style)
                .responseSelectableText(source.text, separator: "", excluding: source.excludedOffsets)
        })
        defer { window.isHidden = true }
        let input = try XCTUnwrap(selectionInputs(in: host.view).first)
        input.selectAll(nil)
        XCTAssertEqual(input.text(in: try XCTUnwrap(input.selectedTextRange)), "Before  after 👩🏽‍💻")
        let glyphs = try XCTUnwrap(input.leaves.allObjects.first?.geometry).glyphs
        XCTAssertEqual(glyphs.map { NSMaxRange($0.range) }.max(), selected.utf16.count)
        let emoji = (selected as NSString).range(of: "👩🏽‍💻")
        XCTAssertFalse(input.selectionRects(for: ResponseTextRange(emoji)).isEmpty)
    }

    func testChangingSelectionIdentityClearsPreviousRange() async throws {
        func content(_ identity: String) -> some View {
            ResponseTextSelection(identity: identity) { Text("Same text").responseSelectableText("Same text") }
        }
        let (window, host) = await renderedHost(content("server-a/session-a/message-a"))
        defer { window.isHidden = true }
        let input = try XCTUnwrap(selectionInputs(in: host.view).first)
        input.selectAll(nil)
        XCTAssertNotNil(input.selectedTextRange)
        host.rootView = AnyView(content("server-b/session-b/message-b"))
        await draw(window, host: host)
        XCTAssertTrue(selectionInputs(in: host.view).allSatisfy { $0.selectedTextRange == nil })
    }

    #if targetEnvironment(macCatalyst)
    func testPointerSelectionSpansParagraphsAndClearsOnResign() async throws {
        let (window, host) = await renderedHost(ResponseTextSelection(identity: "pointer") {
            VStack(alignment: .leading) {
                Text("First paragraph").responseSelectableText("First paragraph", separator: "\n\n")
                Text("Second paragraph").responseSelectableText("Second paragraph", separator: "")
            }
        })
        defer { window.isHidden = true }
        let input = try XCTUnwrap(selectionInputs(in: host.view).first)
        let start = input.caretRect(for: input.beginningOfDocument)
        let end = input.caretRect(for: input.endOfDocument)
        input.beginPointerSelection(at: CGPoint(x: start.minX + 0.1, y: start.midY))
        input.extendPointerSelection(to: CGPoint(x: end.maxX, y: end.midY))
        XCTAssertEqual(input.text(in: try XCTUnwrap(input.selectedTextRange)), "First paragraph\n\nSecond paragraph")
        XCTAssertTrue(input.resignFirstResponder())
        XCTAssertNil(input.selectedTextRange)
        let hostInteractions = input.textInputView.interactions
        XCTAssertFalse(hostInteractions.contains { $0 is UITextInteraction })
        input.selectWord(at: CGPoint(x: start.minX + 1, y: start.midY))
        XCTAssertEqual(input.text(in: try XCTUnwrap(input.selectedTextRange)), "First")
        _ = input.resignFirstResponder()
        input.beginPointerSelection(at: CGPoint(x: -100, y: -100))
        input.extendPointerSelection(to: CGPoint(x: end.maxX, y: end.midY))
        XCTAssertNil(input.selectedTextRange)
    }
    #endif

    private func selectionInputs(in view: UIView) -> [ResponseSelectionInput] {
        if let input = view as? ResponseSelectionInput { return [input] }
        return view.subviews.flatMap { selectionInputs(in: $0) }
    }

    private func renderedHost<V: View>(_ view: V) async -> (UIWindow, UIHostingController<AnyView>) {
        let host = UIHostingController(rootView: AnyView(view))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 900))
        window.rootViewController = host
        window.makeKeyAndVisible()
        await draw(window, host: host)
        return (window, host)
    }

    private func draw(_ window: UIWindow, host: UIViewController) async {
        let rendered = expectation(description: "Selection fixture rendered")
        DispatchQueue.main.async {
            host.view.layoutIfNeeded()
            _ = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            rendered.fulfill()
        }
        await fulfillment(of: [rendered], timeout: 5)
    }

}
