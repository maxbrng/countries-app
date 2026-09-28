//
//  MapSheetChainUITests.swift
//  CountriesUITests
//
//  Created by Max Breuning on 28.09.26.
//

import XCTest

/// Exercises the map's stacked sheet chain through the interactions that have regressed before:
/// rotating the device while sheets are up, and leaving the screen and coming back.
///
/// Both were previously checked by recording the simulator and stepping through the frames. A
/// test does the same job repeatably, and attaches a screenshot at each step so the recording is
/// still there to look at when something does break.
///
/// - Note: Leaving is driven by the close button, not by the interactive back-swipe. On the map
///   screen the swipe is currently swallowed by the map's own pan recogniser - it pans the world
///   instead of popping - while the same swipe pops every other pushed screen. That is a bug in
///   its own right and not this suite's to assert; what matters here is that the exit path tears
///   the sheet stack down, and the close button and the swipe share it.
///
/// - Note: Launched with `-hasCompletedOnboarding YES` so the app opens on the dashboard instead
///   of the first-launch flow. `UserDefaults` reads launch arguments from its argument domain,
///   which is what `@AppStorage` then sees.
final class MapSheetChainUITests: XCTestCase {

    // MARK: - Constants

    /// How long an element is waited for before the step counts as failed.
    private static let elementTimeout: TimeInterval = 10

    /// Pause after a rotation, long enough for the transition coordinator's completion to run.
    private static let rotationSettleDuration: TimeInterval = 2

    /// Where a tap lands to select a country. Over land in both orientations.
    private static let countryTapPoint = CGVector(dx: 0.5, dy: 0.45)

    // MARK: - Fixture

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES"]
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        app = nil
    }

    // MARK: - Helpers

    /// Opens the map screen from the dashboard card and waits for the base search sheet.
    private func openMapScreen() {

        app.launch()

        let preview = app.descendants(matching: .any)["World map"]
        XCTAssertTrue(preview.waitForExistence(timeout: Self.elementTimeout),
                      "The dashboard map preview never appeared")
        preview.tap()

        XCTAssertTrue(searchField.waitForExistence(timeout: Self.elementTimeout),
                      "The base search sheet never came up on the map screen")
    }

    /// The base sheet's search field, which is the cheapest proof that the base sheet is up.
    private var searchField: XCUIElement {
        app.textFields["Search countries"]
    }

    /// Attaches a screenshot under `name` so a failed run can be looked at rather than guessed at.
    private func attachScreenshot(named name: String) {

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Rotates the device and gives the transition coordinator time to finish.
    ///
    /// - Parameter orientation: The orientation to turn to.
    private func rotate(to orientation: UIDeviceOrientation) {

        XCUIDevice.shared.orientation = orientation
        Thread.sleep(forTimeInterval: Self.rotationSettleDuration)
    }

    // MARK: - Tests

    func test_baseSheet_survivesARotationInBothDirections() throws {

        // Arrange
        openMapScreen()
        attachScreenshot(named: "01-portrait-base-sheet")

        // Act / Assert: landscape.
        rotate(to: .landscapeLeft)
        attachScreenshot(named: "02-landscape-base-sheet")
        XCTAssertTrue(searchField.exists, "The base sheet did not survive the turn to landscape")
        XCTAssertTrue(searchField.isHittable, "The base sheet is off screen in landscape")

        // Act / Assert: back to portrait.
        rotate(to: .portrait)
        attachScreenshot(named: "03-portrait-again-base-sheet")
        XCTAssertTrue(searchField.exists, "The base sheet did not survive the turn back to portrait")
        XCTAssertTrue(searchField.isHittable, "The base sheet is off screen in portrait")
    }

    func test_countrySheet_survivesARotationOnTopOfTheBaseSheet() throws {

        // Arrange: a secondary sheet stacked on the base sheet.
        openMapScreen()
        app.coordinate(withNormalizedOffset: Self.countryTapPoint).tap()

        let visitedButton = app.buttons["Visited"]
        XCTAssertTrue(visitedButton.waitForExistence(timeout: Self.elementTimeout),
                      "Tapping the map did not open the country sheet")
        attachScreenshot(named: "04-portrait-country-sheet")

        // Act
        rotate(to: .landscapeLeft)
        attachScreenshot(named: "05-landscape-country-sheet")

        // Assert: the sheet on top of the chain is still there and still reachable. The base
        // sheet under it is deliberately not asserted - UIKit takes a covered sheet out of the
        // accessibility tree, so its absence there says nothing about the stack.
        XCTAssertTrue(visitedButton.exists, "The country sheet did not survive the rotation")
        XCTAssertTrue(visitedButton.isHittable, "The country sheet is off screen in landscape")

        rotate(to: .portrait)
        attachScreenshot(named: "06-portrait-again-country-sheet")
        XCTAssertTrue(visitedButton.exists, "The country sheet did not survive the turn back")
    }

    func test_closingTheMap_takesTheSheetsWithIt() throws {

        // Arrange
        openMapScreen()

        // Act
        app.buttons["Close"].tap()

        // Assert: the dashboard is back and no sheet came with it.
        let dashboardTitle = app.staticTexts["Your Countries"]
        XCTAssertTrue(dashboardTitle.waitForExistence(timeout: Self.elementTimeout),
                      "Closing did not pop the map screen")
        attachScreenshot(named: "07-after-closing")
        XCTAssertFalse(searchField.exists, "A sheet outlived the map screen it belonged to")
    }

    func test_mapScreen_canBeReenteredAfterLeavingIt() throws {

        // The exit path resets the whole sheet stack; this is what proves it reset it to a state
        // the next visit can present from.
        openMapScreen()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Your Countries"].waitForExistence(timeout: Self.elementTimeout))

        // Act: straight back in.
        let preview = app.descendants(matching: .any)["World map"]
        XCTAssertTrue(preview.waitForExistence(timeout: Self.elementTimeout))
        preview.tap()

        // Assert
        XCTAssertTrue(searchField.waitForExistence(timeout: Self.elementTimeout),
                      "The base sheet did not come back on the second visit")
        attachScreenshot(named: "08-second-visit-base-sheet")
    }

    func test_countrySheet_isDismissedAndTheBaseSheetComesBack() throws {

        // Arrange
        openMapScreen()
        app.coordinate(withNormalizedOffset: Self.countryTapPoint).tap()
        XCTAssertTrue(app.buttons["Visited"].waitForExistence(timeout: Self.elementTimeout),
                      "Tapping the map did not open the country sheet")

        // Act: the close button in the country sheet's navigation bar. Found by identifier on
        // purpose - the map screen's own close button carries the same label, and tapping that
        // one leaves the screen rather than the sheet.
        app.buttons["mapSheetCloseButton"].tap()

        // Assert: the stack converged back on the base sheet alone.
        XCTAssertTrue(searchField.waitForExistence(timeout: Self.elementTimeout),
                      "The base sheet did not come back after the country sheet closed")
        attachScreenshot(named: "09-base-sheet-after-country-sheet-closed")
    }
}
