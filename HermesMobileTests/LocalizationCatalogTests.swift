import XCTest

/// Guards the App Localization effort (issues #290, #291, …): every translatable key in
/// `Localizable.xcstrings` must carry a non-empty value in **each shipped language**. This
/// catches a dropped/forgotten translation before it ships as a blank string in that
/// language's build.
///
/// The catalog is JSON on disk; we read the source file directly (located relative to
/// this test via `#filePath`) so the guard runs without bundling the catalog into the
/// test target. Keys explicitly marked `"shouldTranslate": false` (brand names,
/// format-only artifacts) are intentionally skipped.
///
/// When a new language is added to the catalog, add its code to `shippedLanguages` so the
/// guard covers it too.
final class LocalizationCatalogTests: XCTestCase {

    /// Non-English languages compiled into the app. Keep in sync with `knownRegions` in the
    /// project file and the languages present in `Localizable.xcstrings`.
    private static let shippedLanguages = ["de", "es", "fr", "it", "pl", "pt-BR", "nl", "tr", "ru", "ja", "zh-Hans", "ko", "ar", "he", "ur", "zh-Hant", "zh-HK"]

    private func resourceURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HermesMobileTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(relativePath)
    }

    private func catalogURL() -> URL {
        // .../HermesMobileTests/LocalizationCatalogTests.swift
        //   -> repo root -> HermesMobile/Resources/Localizable.xcstrings
        resourceURL("HermesMobile/Resources/Localizable.xcstrings")
    }

    /// True iff the language entry holds a non-empty value — either a plain `stringUnit` or
    /// a `plural` variation where every category is filled.
    private func hasNonEmptyValue(_ localization: [String: Any]) -> Bool {
        if let value = (localization["stringUnit"] as? [String: Any])?["value"] as? String {
            return !value.isEmpty
        }
        if let plural = ((localization["variations"] as? [String: Any])?["plural"] as? [String: Any]), !plural.isEmpty {
            return plural.values.allSatisfy { cat in
                let value = ((cat as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
                return !(value ?? "").isEmpty
            }
        }
        return false
    }

    func testShippedLanguageTranslationsHaveNoEmptyValues() throws {
        let url = catalogURL()
        guard let data = try? Data(contentsOf: url) else {
            throw XCTSkip("Could not read String Catalog at \(url.path); skipping — the source tree is not present in this environment (e.g. on a physical device or a remote test runner). Runs on the simulator/CI where the checkout exists.")
        }
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["sourceLanguage"] as? String, "en", "Development language should remain English.")
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        XCTAssertGreaterThan(strings.count, 200, "Catalog is unexpectedly small — string extraction may have regressed.")

        for language in Self.shippedLanguages {
            var missing: [String] = []
            var translated = 0

            for (key, rawEntry) in strings {
                guard let entry = rawEntry as? [String: Any] else { continue }
                if entry["shouldTranslate"] as? Bool == false { continue }   // intentionally excluded

                guard let localization = (entry["localizations"] as? [String: Any])?[language] as? [String: Any] else {
                    missing.append(key)
                    continue
                }
                hasNonEmptyValue(localization) ? (translated += 1) : missing.append(key)
            }

            XCTAssertTrue(missing.isEmpty,
                          "[\(language)] \(missing.count) translatable key(s) have no value: \(missing.sorted())")
            XCTAssertGreaterThan(translated, 200, "[\(language)] Far fewer translations than expected — something dropped.")
        }
    }

    func testAppShortcutPhrasesHaveDedicatedCatalogEntries() throws {
        let url = resourceURL("HermesMobile/Resources/AppShortcuts.xcstrings")
        let data = try Data(contentsOf: url)

        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["sourceLanguage"] as? String, "en")
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        let expectedPhrases = [
            "New chat in ${applicationName}",
            "New ${applicationName} chat",
            "Start a new chat in ${applicationName}",
            "New voice chat in ${applicationName}",
            "New ${applicationName} voice chat",
            "Start a voice chat in ${applicationName}",
            "New ${profile} chat in ${applicationName}",
            "Start a new ${profile} chat in ${applicationName}",
            "New chat in ${profile} on ${applicationName}"
        ]

        XCTAssertEqual(Set(strings.keys), Set(expectedPhrases))

        for phrase in expectedPhrases {
            let entry = try XCTUnwrap(strings[phrase] as? [String: Any], phrase)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], phrase)
            for language in Self.shippedLanguages + ["en"] {
                let localization = try XCTUnwrap(localizations[language] as? [String: Any], "[\(language)] \(phrase)")
                XCTAssertTrue(hasNonEmptyValue(localization), "[\(language)] \(phrase) is empty")
            }
        }
    }

    func testNotificationPermissionTranslationsKeepAReplaceablePlatformName() throws {
        let data = try Data(contentsOf: catalogURL())
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        let platformSpecificKeys = [
            "iOS notifications allowed.",
            "iOS permission not requested.",
            "iOS notifications disabled."
        ]

        for key in platformSpecificKeys {
            XCTAssertEqual(
                key.components(separatedBy: "iOS").count - 1,
                1,
                "The source key must contain exactly one replaceable iOS platform name."
            )

            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)

            for language in Self.shippedLanguages {
                let localization = try XCTUnwrap(
                    localizations[language] as? [String: Any],
                    "[\(language)] \(key)"
                )
                let stringUnit = try XCTUnwrap(
                    localization["stringUnit"] as? [String: Any],
                    "[\(language)] \(key)"
                )
                let value = try XCTUnwrap(
                    stringUnit["value"] as? String,
                    "[\(language)] \(key)"
                )

                XCTAssertEqual(
                    value.components(separatedBy: "iOS").count - 1,
                    1,
                    "[\(language)] \(key) must contain exactly one platform name so Catalyst can substitute Mac."
                )
            }
        }
    }

    func testOnboardingHasCompleteLocalizedCopyForEachClientPlatform() throws {
        let data = try Data(contentsOf: catalogURL())
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        let platformSpecificKeyPairs = [
            ("Chat with your Hermes agent from iPhone", "Chat with your Hermes agent from Mac"),
            ("Install Tailscale on iPhone", "Install Tailscale on Mac"),
            (
                "Install Tailscale on your iPhone and sign into the same tailnet as your server. Your agent will reply with the exact URL to use on the next screen.",
                "Install Tailscale on your Mac and sign into the same tailnet as your server. Your agent will reply with the exact URL to use on the next screen."
            ),
            ("Your Hermes agent, reachable from iPhone over Tailscale.", "Your Hermes agent, reachable from Mac over Tailscale.")
        ]

        for (iPhoneKey, macKey) in platformSpecificKeyPairs {
            for key in [iPhoneKey, macKey] {
                let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
                let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)

                for language in Self.shippedLanguages {
                    let localization = try XCTUnwrap(
                        localizations[language] as? [String: Any],
                        "[\(language)] \(key)"
                    )
                    XCTAssertTrue(hasNonEmptyValue(localization), "[\(language)] \(key) is empty")

                    if key == macKey {
                        let value = ((localization["stringUnit"] as? [String: Any])?["value"] as? String) ?? ""
                        XCTAssertFalse(value.contains("iPhone"), "[\(language)] \(key) still contains iPhone copy")
                        XCTAssertFalse(value.contains("iPhonie"), "[\(language)] \(key) still contains iPhone copy")
                    }
                }
            }
        }
    }

    func testKanbanCardDetailCopyIsLocalizedInEveryShippedLanguage() throws {
        let data = try Data(contentsOf: catalogURL())
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        let detailKeys = [
            "Card ID", "Comment", "Comment cannot be blank.", "Created", "Dependencies",
            "Description", "Dispatch Runs", "Events", "Maximum Runtime", "Metadata",
            "Operational History", "Operational Metadata", "Outcome Uncertain", "Priority",
            "Run ID", "Updated", "Worker ID", "Worker Log",
            "This Board no longer exists. Return to Kanban to choose another Board.",
            "This Card no longer exists on this Board. The Board has been refreshed."
        ]

        for key in detailKeys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            for language in Self.shippedLanguages {
                let localization = try XCTUnwrap(
                    localizations[language] as? [String: Any],
                    "[\(language)] \(key)"
                )
                XCTAssertTrue(hasNonEmptyValue(localization), "[\(language)] \(key) is empty")
            }
        }
    }

    func testKanbanCardEditorCopyIsLocalizedInEveryShippedLanguage() throws {
        let data = try Data(contentsOf: catalogURL())
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        let editorKeys = [
            "Edit Card", "New Card", "Title", "Title is required.", "Assignment", "Execution",
            "Prerequisite", "Create Ready, Unassigned Card?", "Reload Server Version",
            "Move Card Out of Running?", "Moving this Card out of Running may clear its claim and worker state.",
            "Review and Overwrite", "This Card changed on the server after the editor opened. Your draft has been preserved.",
            "Workspace, Skills, Maximum Runtime, and Prerequisite are set when the Card is created and cannot be edited here."
        ]

        for key in editorKeys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            for language in Self.shippedLanguages {
                let localization = try XCTUnwrap(
                    localizations[language] as? [String: Any],
                    "[\(language)] \(key)"
                )
                XCTAssertTrue(hasNonEmptyValue(localization), "[\(language)] \(key) is empty")
                let translatedValue = (localization["stringUnit"] as? [String: Any])?["value"] as? String
                XCTAssertNotEqual(translatedValue, key, "[\(language)] \(key) still uses the English source value")
            }
        }
    }
}
