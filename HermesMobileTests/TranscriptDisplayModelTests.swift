import XCTest
import AVFoundation
import ImageIO
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
@testable import HermesMobile

final class TranscriptMessageTests: XCTestCase {
    @MainActor
    func testCacheFirstTranscriptFrameCommitPerformanceDiagnostic() async throws {
        let messages = PerformanceBaselineFixtures.transcriptMessages()
        let transcriptMessages = ChatViewModel.transcriptMessages(from: messages)
        let clock = ContinuousClock()
        var milliseconds: [Double] = []
        var synchronousLayoutMilliseconds: [Double] = []
        var evaluatedRowCounts: [Int] = []

        let totalIterations = PerformanceBaselineFixtures.warmupCount
            + PerformanceBaselineFixtures.sampleCount
        for generation in 1...totalIterations {
            var evaluatedRowCount = 0
            let marker = CacheFirstRenderMarker(sessionID: "diagnostic", generation: generation)
            let committed = expectation(description: "cache-first frame committed \(generation)")
            let start = clock.now
            let view = makeDiagnosticTranscriptView(
                messages: messages,
                transcriptMessages: transcriptMessages,
                marker: marker,
                onMessageRowEvaluation: { _ in evaluatedRowCount += 1 }
            ) { committedMarker in
                XCTAssertEqual(committedMarker, marker)
                let duration = start.duration(to: clock.now)
                if generation > PerformanceBaselineFixtures.warmupCount {
                    milliseconds.append(Double(duration.components.seconds) * 1_000
                        + Double(duration.components.attoseconds) / 1_000_000_000_000_000)
                    evaluatedRowCounts.append(evaluatedRowCount)
                }
                committed.fulfill()
            }
            let windowScene = try XCTUnwrap(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let window = UIWindow(windowScene: windowScene)
            window.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
            window.rootViewController = UIHostingController(rootView: view)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            let layoutDuration = start.duration(to: clock.now)
            if generation > PerformanceBaselineFixtures.warmupCount {
                synchronousLayoutMilliseconds.append(
                    Double(layoutDuration.components.seconds) * 1_000
                        + Double(layoutDuration.components.attoseconds) / 1_000_000_000_000_000
                )
            }

            await fulfillment(of: [committed], timeout: 2)
            window.isHidden = true
        }

        XCTAssertEqual(milliseconds.count, 15)
        let commitSummary = PerformanceSampleSummary(
            nanoseconds: milliseconds.map { UInt64($0 * 1_000_000) }
        )
        let layoutSummary = PerformanceSampleSummary(
            nanoseconds: synchronousLayoutMilliseconds.map { UInt64($0 * 1_000_000) }
        )
        let result = "TranscriptCommittedFrameBaseline fixture=\(PerformanceBaselineFixtures.identity) samples=\(commitSummary.sampleCount) commitMedianMs=\(commitSummary.medianMilliseconds) commitP95Ms=\(commitSummary.p95Milliseconds) layoutMedianMs=\(layoutSummary.medianMilliseconds) layoutP95Ms=\(layoutSummary.p95Milliseconds) evaluatedRows=\(evaluatedRowCounts)"
        print("[PERF] \(result)")
        XCTContext.runActivity(named: result) { _ in }
    }

    func testTranscriptDisplayModelConstructionPerformanceDiagnostic() {
        let messages = (0..<50).map { index in
            ChatMessage(
                role: index.isMultiple(of: 7) ? "tool" : (index.isMultiple(of: 2) ? "user" : "assistant"),
                content: String(repeating: "Long cached transcript content \(index). ", count: 30),
                timestamp: Double(index),
                messageId: "message-\(index)",
                toolCallId: index.isMultiple(of: 7) ? "tool-\(index)" : nil,
                reasoning: String(repeating: "Reasoning \(index). ", count: 20)
            )
        }
        let expectedCount = ChatViewModel.transcriptMessages(from: messages, messageOffset: 900).count
        let clock = ContinuousClock()
        var milliseconds: [Double] = []

        for _ in 0..<100 {
            let start = clock.now
            let result = ChatViewModel.transcriptMessages(from: messages, messageOffset: 900)
            let duration = start.duration(to: clock.now)
            milliseconds.append(Double(duration.components.seconds) * 1_000
                + Double(duration.components.attoseconds) / 1_000_000_000_000_000)
            XCTAssertEqual(result.count, expectedCount)
        }

        XCTContext.runActivity(
            named: "TranscriptDisplayModelBenchmark milliseconds=\(milliseconds)"
        ) { _ in }
    }

    func testTranscriptMessagesHideToolRowsAndPreserveLoadedIndices() {
        let messages = [
            ChatMessage(role: "user", content: "Plan it", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Working on it", timestamp: 2, messageId: "a1"),
            ChatMessage(
                role: "tool",
                content: #"{"success":true,"diff":"..."}"#,
                timestamp: 3,
                messageId: "t1",
                toolCallId: "tool-1"
            ),
            ChatMessage(role: "assistant", content: "Done. Here's what changed.", timestamp: 4, messageId: "a2")
        ]

        let transcriptMessages = ChatViewModel.transcriptMessages(from: messages)

        XCTAssertEqual(transcriptMessages.map(\.loadedIndex), [0, 1, 3])
        XCTAssertEqual(transcriptMessages.map(\.message.id), ["u1", "a1", "a2"])
    }

    func testTranscriptMessagesCanHideActiveStreamingAssistantTurn() {
        let messages = [
            ChatMessage(role: "user", content: "Use tools", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "", timestamp: 2, messageId: "stream-1"),
            ChatMessage(
                role: "tool",
                content: #"{"success":true}"#,
                timestamp: 3,
                messageId: "t1",
                toolCallId: "tool-1"
            ),
            ChatMessage(role: "assistant", content: "Older answer", timestamp: 4, messageId: "a2")
        ]

        let transcriptMessages = ChatViewModel.transcriptMessages(
            from: messages,
            hidingStreamingAssistantID: "stream-1"
        )

        XCTAssertEqual(transcriptMessages.map(\.loadedIndex), [0, 3])
        XCTAssertEqual(transcriptMessages.map(\.message.id), ["u1", "a2"])
    }

    func testTranscriptMessagesKeepStreamingAssistantAnchorStableAcrossContentUpdates() {
        let initialMessages = [
            ChatMessage(role: "user", content: "Write a long answer", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "", timestamp: 2, messageId: "stream-1")
        ]
        let updatedMessages = [
            ChatMessage(role: "user", content: "Write a long answer", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "First streamed token.", timestamp: 2, messageId: "stream-1")
        ]

        let initialTranscriptMessages = ChatViewModel.transcriptMessages(from: initialMessages)
        let updatedTranscriptMessages = ChatViewModel.transcriptMessages(from: updatedMessages)

        XCTAssertEqual(initialTranscriptMessages.map(\.anchorID), ["u1", "stream-1"])
        XCTAssertEqual(updatedTranscriptMessages.map(\.anchorID), ["u1", "stream-1"])
        XCTAssertEqual(initialTranscriptMessages.map(\.id), updatedTranscriptMessages.map(\.id))
        XCTAssertEqual(initialTranscriptMessages.map(\.loadedIndex), updatedTranscriptMessages.map(\.loadedIndex))
    }

    func testTranscriptMessagesKeepRenderIDStableWhenServerReplacesStreamingAssistantID() {
        let streamingMessages = [
            ChatMessage(role: "user", content: "Finish the summary", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Working summary", timestamp: 2, messageId: "stream-1")
        ]
        let completedMessages = [
            ChatMessage(role: "user", content: "Finish the summary", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Final summary", timestamp: 2, messageId: "assistant-1")
        ]

        let streamingTranscriptMessages = ChatViewModel.transcriptMessages(from: streamingMessages)
        let completedTranscriptMessages = ChatViewModel.transcriptMessages(from: completedMessages)

        XCTAssertEqual(streamingTranscriptMessages.map(\.id), completedTranscriptMessages.map(\.id))
        XCTAssertEqual(streamingTranscriptMessages.map(\.anchorID), ["u1", "stream-1"])
        XCTAssertEqual(completedTranscriptMessages.map(\.anchorID), ["u1", "assistant-1"])
    }

    func testTranscriptMessagesUseRawAnchorForNilMessageIDsIndependentOfContent() {
        let initialMessages = [
            ChatMessage(role: "user", content: "Hello", timestamp: 1, messageId: nil),
            ChatMessage(role: "assistant", content: "", timestamp: 2, messageId: nil)
        ]
        let updatedMessages = [
            ChatMessage(role: "user", content: "Hello", timestamp: 1, messageId: nil),
            ChatMessage(role: "assistant", content: "A streamed response.", timestamp: 2, messageId: nil)
        ]

        let initialTranscriptMessages = ChatViewModel.transcriptMessages(
            from: initialMessages,
            messageOffset: 10
        )
        let updatedTranscriptMessages = ChatViewModel.transcriptMessages(
            from: updatedMessages,
            messageOffset: 10
        )

        XCTAssertEqual(initialTranscriptMessages.map(\.anchorID), ["raw:10", "raw:11"])
        XCTAssertEqual(updatedTranscriptMessages.map(\.anchorID), ["raw:10", "raw:11"])
        XCTAssertEqual(initialTranscriptMessages.map(\.id), updatedTranscriptMessages.map(\.id))
    }

    func testTranscriptMessagesKeepRenderIDsStableWhenOlderMessagesPrepend() {
        let initialWindow = [
            ChatMessage(role: "assistant", content: "Earlier answer", timestamp: 1, messageId: "a1"),
            ChatMessage(role: "user", content: "Follow up", timestamp: 2, messageId: "u2"),
            ChatMessage(role: "assistant", content: "Latest answer", timestamp: 3, messageId: "a2")
        ]
        let expandedWindow = [
            ChatMessage(role: "user", content: "First question", timestamp: 0, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Earlier answer", timestamp: 1, messageId: "a1"),
            ChatMessage(role: "user", content: "Follow up", timestamp: 2, messageId: "u2"),
            ChatMessage(role: "assistant", content: "Latest answer", timestamp: 3, messageId: "a2")
        ]

        let initialTranscriptMessages = ChatViewModel.transcriptMessages(
            from: initialWindow,
            messageOffset: 1
        )
        let expandedTranscriptMessages = ChatViewModel.transcriptMessages(
            from: expandedWindow,
            messageOffset: 0
        )

        XCTAssertEqual(initialTranscriptMessages.map(\.id), ["transcript:1", "transcript:2", "transcript:3"])
        XCTAssertEqual(expandedTranscriptMessages.map(\.id), ["transcript:0", "transcript:1", "transcript:2", "transcript:3"])

        let initialRenderIDsByMessageID = Dictionary(
            uniqueKeysWithValues: initialTranscriptMessages.compactMap { transcriptMessage in
                transcriptMessage.message.messageId.map { ($0, transcriptMessage.id) }
            }
        )
        for expandedTranscriptMessage in expandedTranscriptMessages {
            guard let messageID = expandedTranscriptMessage.message.messageId,
                  let initialRenderID = initialRenderIDsByMessageID[messageID]
            else { continue }

            XCTAssertEqual(
                expandedTranscriptMessage.id,
                initialRenderID,
                "renderID should stay stable for message \(messageID)"
            )
        }
    }

    func testTranscriptMessagesPreserveMessagesWithNilMessageIDsWhenNoStreamingTurnHidden() {
        let messages = [
            ChatMessage(role: "user", content: "Hello", timestamp: 1, messageId: nil),
            ChatMessage(role: "assistant", content: "Hi", timestamp: 2, messageId: nil),
            ChatMessage(
                role: "tool",
                content: #"{"success":true}"#,
                timestamp: 3,
                messageId: nil,
                toolCallId: "tool-1"
            )
        ]

        let transcriptMessages = ChatViewModel.transcriptMessages(from: messages)

        XCTAssertEqual(transcriptMessages.map(\.loadedIndex), [0, 1])
        XCTAssertEqual(transcriptMessages.map(\.message.role), ["user", "assistant"])
    }

    @MainActor
    private func makeDiagnosticTranscriptView(
        messages: [ChatMessage],
        transcriptMessages: [TranscriptMessage],
        marker: CacheFirstRenderMarker,
        onMessageRowEvaluation: @escaping (ChatMessage) -> Void = { _ in },
        onCommitted: @escaping (CacheFirstRenderMarker) -> Void
    ) -> ChatTranscriptView {
        ChatTranscriptView(
            isLoading: true,
            errorMessage: nil,
            messages: messages,
            displayedTranscriptMessages: transcriptMessages,
            cacheFirstRenderMarker: marker,
            compressionReferenceCard: nil,
            reasoningGroups: [],
            completedToolCallGroupsForAnchor: { _ in [] },
            liveReasoningText: "",
            reasoningAnchorMessageID: nil,
            liveToolCalls: [],
            toolCallAnchorMessageID: nil,
            streamingAssistantMessageID: nil,
            activeStreamRecoveryState: .idle,
            clarificationPrompt: nil,
            isRespondingToClarification: false,
            clarificationErrorMessage: nil,
            hidesRunStatusAccessibility: false,
            keepsComposerFocusedOnInteraction: false,
            showsThinkingAndToolCards: true,
            showsAssistantTypingIndicator: false,
            showsScrollToBottomButton: false,
            shouldFollowLatestMessage: true,
            latestTranscriptMessageRole: "assistant",
            isScrolledNearBottom: true,
            activeStreamID: nil,
            streamingScrollTrigger: 0,
            cacheFirstReconcileScrollToken: 0,
            bottomAnchorID: "diagnostic-bottom",
            transcriptMessageSpacing: 14,
            transcriptBlockSpacing: 8,
            transcriptBottomInsetHeight: 0,
            scrollToBottomButtonBottomPadding: 0,
            localAttachmentPreviews: [:],
            listeningMessageID: nil,
            isViewingCachedData: false,
            hasOlderMessages: true,
            isLoadingOlderMessages: false,
            isRegeneratingMessage: false,
            isEditingMessage: false,
            isForkingMessage: false,
            loadAttachmentImage: { _ in nil },
            loadAttachmentData: { _ in nil },
            loadTranscriptMediaImage: { _ in nil },
            loadTranscriptMediaData: { _ in nil },
            transcriptMediaCacheNamespace: "diagnostic",
            actionContext: { _, _ in nil },
            shouldRenderMessageRow: { message in
                onMessageRowEvaluation(message)
                return true
            },
            onLoadMessages: {},
            onLoadOlderMessages: { false },
            onUpdateScrollMetrics: { _ in },
            onCacheFirstFrameCommitted: onCommitted,
            onDismissKeyboard: {},
            onScrollToBottom: { _ in },
            onScrollToLatestTranscriptMessage: { _ in },
            onScrollToLatestContent: { _, _ in },
            onPreviewAttachment: { _, _ in },
            onPreviewTranscriptMedia: { _ in },
            onToggleListening: { _ in },
            onSubmitClarification: { _ in },
            onSelectText: { _ in },
            onRegenerate: { _ in },
            onEdit: { _ in },
            onFork: { _ in },
            onCopy: { _ in }
        )
    }
}

final class ChatTranscriptDisplaySettingsTests: XCTestCase {
    func testTypingIndicatorStaysHiddenBehindVisibleThinkingAndToolCards() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: false,
            liveReasoningText: "Inspecting files",
            hasLiveToolCalls: false,
            showsThinkingAndToolCards: true
        ))

        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: false,
            liveReasoningText: "",
            hasLiveToolCalls: true,
            showsThinkingAndToolCards: true
        ))
    }

    func testTypingIndicatorShowsWhenHiddenCardsAreOnlyLiveActivity() {
        XCTAssertTrue(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: false,
            liveReasoningText: "Inspecting files",
            hasLiveToolCalls: true,
            showsThinkingAndToolCards: false
        ))

        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: true,
            liveReasoningText: "Inspecting files",
            hasLiveToolCalls: true,
            showsThinkingAndToolCards: false
        ))
    }

    func testTypingIndicatorHidesBehindPendingClarificationPrompt() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: false,
            hasPendingClarificationPrompt: true,
            liveReasoningText: "",
            hasLiveToolCalls: false,
            showsThinkingAndToolCards: false
        ))
    }

    func testStreamingBubbleRenderingDoesNotMatchNilMessageIDs() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldUseStreamingBubbleRendering(
            hasActiveStream: true,
            messageRole: "user",
            messageID: nil,
            streamingAssistantMessageID: nil
        ))

        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldUseStreamingBubbleRendering(
            hasActiveStream: true,
            messageRole: "assistant",
            messageID: nil,
            streamingAssistantMessageID: nil
        ))
    }

    func testStreamingBubbleRenderingMatchesActiveStreamingAssistant() {
        XCTAssertTrue(ChatTranscriptDisplaySettings.shouldUseStreamingBubbleRendering(
            hasActiveStream: true,
            messageRole: "assistant",
            messageID: "stream-1",
            streamingAssistantMessageID: "stream-1"
        ))

        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldUseStreamingBubbleRendering(
            hasActiveStream: true,
            messageRole: "assistant",
            messageID: "assistant-1",
            streamingAssistantMessageID: "stream-1"
        ))
    }

    func testCardExpansionFollowsStartExpandedPreferenceUntilToggled() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.isCardExpanded(userToggled: nil, startsExpanded: false))
        XCTAssertTrue(ChatTranscriptDisplaySettings.isCardExpanded(userToggled: nil, startsExpanded: true))
    }

    func testCardExpansionTapOverrideWinsOverPreference() {
        XCTAssertTrue(ChatTranscriptDisplaySettings.isCardExpanded(userToggled: true, startsExpanded: false))
        XCTAssertFalse(ChatTranscriptDisplaySettings.isCardExpanded(userToggled: false, startsExpanded: true))
    }

    func testCardStartExpandedKeysAreStableAndDistinct() {
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.thinkingCardsStartExpandedKey,
            "chatTranscript.thinkingCardsStartExpanded"
        )
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.toolCardsStartExpandedKey,
            "chatTranscript.toolCardsStartExpanded"
        )
        XCTAssertNotEqual(
            ChatTranscriptDisplaySettings.thinkingCardsStartExpandedKey,
            ChatTranscriptDisplaySettings.showsThinkingAndToolCardsKey
        )
    }

    func testHidesAttachmentPathsKeyIsStableAndDistinct() {
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.hidesAttachmentPathsKey,
            "chatTranscript.hidesAttachmentPaths"
        )
        XCTAssertNotEqual(
            ChatTranscriptDisplaySettings.hidesAttachmentPathsKey,
            ChatTranscriptDisplaySettings.showsThinkingAndToolCardsKey
        )
    }

    func testAssistantTurnTimestampsKeyIsStableAndDistinct() {
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.showsAssistantTurnTimestampsKey,
            "chatTranscript.showsAssistantTurnTimestamps"
        )
        XCTAssertNotEqual(
            ChatTranscriptDisplaySettings.showsAssistantTurnTimestampsKey,
            ChatTranscriptDisplaySettings.hidesAttachmentPathsKey
        )
    }

    func testAssistantTurnHeaderShowsForAssistantTextTurnWhenEnabled() {
        XCTAssertTrue(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: "assistant",
            hasTextContent: true,
            isEnabled: true
        ))
    }

    func testAssistantTurnHeaderHiddenWhenToggleOff() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: "assistant",
            hasTextContent: true,
            isEnabled: false
        ))
    }

    func testAssistantTurnHeaderHiddenForEmptyOrToolOnlyAssistantRow() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: "assistant",
            hasTextContent: false,
            isEnabled: true
        ))
    }

    func testAssistantTurnHeaderHiddenForNonAssistantRoles() {
        for role in ["user", "system", "tool", "local_assistant", "local_notice"] {
            XCTAssertFalse(
                ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
                    role: role,
                    hasTextContent: true,
                    isEnabled: true
                ),
                "Header must not render for role \(role)"
            )
        }

        XCTAssertFalse(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: nil,
            hasTextContent: true,
            isEnabled: true
        ))
    }

    func testContentWithoutAttachedFilesMarkerStripsTrailingMarker() {
        // Mirrors the exact format PendingAttachment.chatMessageText appends.
        let sent = "Analyze these files\n\n[Attached files: /tmp/workspace/sample.html, /tmp/workspace/image.jpg]"
        XCTAssertEqual(
            MessageAttachment.contentWithoutAttachedFilesMarker(in: sent),
            "Analyze these files"
        )
    }

    func testContentWithoutAttachedFilesMarkerReturnsEmptyForAttachmentOnlyMessage() {
        // No typed draft: the whole content is just the appended marker.
        let sent = "\n\n[Attached files: /tmp/workspace/image.jpg]"
        XCTAssertEqual(MessageAttachment.contentWithoutAttachedFilesMarker(in: sent), "")
    }

    func testContentWithoutAttachedFilesMarkerPreservesInteriorNewlines() {
        let sent = "line one\nline two\n\n[Attached files: /tmp/a.png]"
        XCTAssertEqual(
            MessageAttachment.contentWithoutAttachedFilesMarker(in: sent),
            "line one\nline two"
        )
    }

    func testContentWithoutAttachedFilesMarkerLeavesPlainMessageUnchanged() {
        let plain = "Just a normal message with no attachments"
        XCTAssertEqual(MessageAttachment.contentWithoutAttachedFilesMarker(in: plain), plain)
    }

    func testContentWithoutAttachedFilesMarkerIgnoresMarkerWithTrailingText() {
        // The parser only treats the marker as a suffix; trailing prose means it
        // is not a real attachment marker, so the content is left untouched.
        let content = "hello\n\n[Attached files: /tmp/a.png] and then more text"
        XCTAssertEqual(MessageAttachment.contentWithoutAttachedFilesMarker(in: content), content)
    }
}

final class ChatActiveRunStatusPolicyTests: XCTestCase {
    func testStatusHidesWhenTranscriptBottomIsVisible() {
        XCTAssertNil(ChatActiveRunStatusPolicy.presentation(
            isStartingChat: false,
            hasActiveStream: true,
            activeStreamRecoveryState: .idle,
            isCancellingStream: false,
            isScrolledNearBottom: true
        ))
    }

    func testStatusShowsActiveRunWhenScrolledAwayFromBottom() {
        let presentation = ChatActiveRunStatusPolicy.presentation(
            isStartingChat: false,
            hasActiveStream: true,
            activeStreamRecoveryState: .idle,
            isCancellingStream: false,
            isScrolledNearBottom: false
        )

        XCTAssertEqual(presentation?.kind, .active)
        XCTAssertEqual(presentation?.label, "Hermes is working")
    }

    func testStatusShowsStartingBeforeStreamIDExists() {
        let presentation = ChatActiveRunStatusPolicy.presentation(
            isStartingChat: true,
            hasActiveStream: false,
            activeStreamRecoveryState: .idle,
            isCancellingStream: false,
            isScrolledNearBottom: false
        )

        XCTAssertEqual(presentation?.kind, .starting)
    }

    func testStatusPrioritizesRecoveryStateOverGenericActiveRun() {
        let presentation = ChatActiveRunStatusPolicy.presentation(
            isStartingChat: false,
            hasActiveStream: true,
            activeStreamRecoveryState: .reconnecting,
            isCancellingStream: false,
            isScrolledNearBottom: false
        )

        XCTAssertEqual(presentation?.kind, .reconnecting)
        XCTAssertEqual(presentation?.accessibilityLabel, "Hermes is reconnecting the response stream")
    }

    func testStatusPrioritizesCancellationOverOtherStates() {
        let presentation = ChatActiveRunStatusPolicy.presentation(
            isStartingChat: true,
            hasActiveStream: true,
            activeStreamRecoveryState: .checking,
            isCancellingStream: true,
            isScrolledNearBottom: false
        )

        XCTAssertEqual(presentation?.kind, .stopping)
    }

    func testStatusHidesWhenIdleAndNoRunIsStarting() {
        XCTAssertNil(ChatActiveRunStatusPolicy.presentation(
            isStartingChat: false,
            hasActiveStream: false,
            activeStreamRecoveryState: .idle,
            isCancellingStream: false,
            isScrolledNearBottom: false
        ))
    }
}

final class AssistantTurnTimestampFormatterTests: XCTestCase {
    // 2021-01-01 14:14:00 UTC
    private let fixedTimestamp: Double = 1_609_510_440
    private let utc = TimeZone(identifier: "UTC")!

    func testFormatsTwelveHourLocaleAsShortTime() {
        let result = AssistantTurnTimestampFormatter.shortTime(
            forUnixTimestamp: fixedTimestamp,
            locale: Locale(identifier: "en_US"),
            timeZone: utc
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("2:14") == true, "Expected 12h time, got \(result ?? "nil")")
        XCTAssertTrue(result?.contains("PM") == true, "Expected PM marker, got \(result ?? "nil")")
    }

    func testFormatsTwentyFourHourLocaleAsShortTime() {
        let result = AssistantTurnTimestampFormatter.shortTime(
            forUnixTimestamp: fixedTimestamp,
            locale: Locale(identifier: "en_GB"),
            timeZone: utc
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("14:14") == true, "Expected 24h time, got \(result ?? "nil")")
        XCTAssertFalse(result?.contains("PM") == true, "24h time must not carry a PM marker")
    }

    func testReturnsNilForNilTimestamp() {
        XCTAssertNil(AssistantTurnTimestampFormatter.shortTime(forUnixTimestamp: nil))
        XCTAssertNil(AssistantTurnTimestampFormatter.shortTime(
            forUnixTimestamp: nil,
            locale: Locale(identifier: "en_US"),
            timeZone: utc
        ))
    }

    func testReturnsNilForNonFiniteTimestamp() {
        XCTAssertNil(AssistantTurnTimestampFormatter.shortTime(forUnixTimestamp: .nan))
        XCTAssertNil(AssistantTurnTimestampFormatter.shortTime(forUnixTimestamp: .infinity))
    }

    func testCurrentLocaleOverloadFormatsFiniteTimestamp() {
        XCTAssertNotNil(AssistantTurnTimestampFormatter.shortTime(forUnixTimestamp: fixedTimestamp))
    }
}

final class ChatTranscriptViewPerformanceGuardTests: XCTestCase {
    func testTranscriptLazilyRealizesLongConversationRows() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HermesMobile/Features/Chat/ChatTranscriptView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let sourceWithoutComments = source
            .replacingOccurrences(of: #"(?s)/\*.*?\*/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)//.*$"#, with: "", options: .regularExpression)

        XCTAssertNotNil(
            sourceWithoutComments.range(
                of: #"\bLazyVStack\s*\(\s*spacing:\s*transcriptMessageSpacing\s*\)"#,
                options: .regularExpression
            ),
            "Long transcripts should not eagerly construct and lay out every Markdown-heavy row."
        )
        XCTAssertNil(
            sourceWithoutComments.range(
                of: #"\bVStack\s*\(\s*spacing:\s*transcriptMessageSpacing\s*\)"#,
                options: .regularExpression
            ),
            "A plain VStack regresses long-session scroll performance by eagerly realizing every transcript row."
        )
        XCTAssertNil(
            sourceWithoutComments.range(
                of: #"\.scrollPosition\s*\("#,
                options: .regularExpression
            ),
            "Keep ScrollViewProxy as the transcript's single programmatic-scroll mechanism; a second scroll-position binding races scroll-to-top and scroll-to-bottom commands."
        )
    }
}
