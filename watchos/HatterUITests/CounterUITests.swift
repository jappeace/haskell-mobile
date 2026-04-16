import XCTest

class CounterUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    func testCounterInitialState() {
        XCTAssert(app.staticTexts["Counter: 0"].waitForExistence(timeout: 15))
        XCTAssert(app.buttons["+"].exists)
        XCTAssert(app.buttons["-"].exists)
    }

    func testTapIncrementsCounter() {
        XCTAssert(app.staticTexts["Counter: 0"].waitForExistence(timeout: 15))
        app.buttons["+"].tap()
        XCTAssert(app.staticTexts["Counter: 1"].waitForExistence(timeout: 10))
    }

    func testTapDecrementsCounter() {
        XCTAssert(app.staticTexts["Counter: 0"].waitForExistence(timeout: 15))
        app.buttons["-"].tap()
        XCTAssert(app.staticTexts["Counter: -1"].waitForExistence(timeout: 10))
    }

    func testFullSequence() {
        XCTAssert(app.staticTexts["Counter: 0"].waitForExistence(timeout: 15))
        app.buttons["+"].tap()
        XCTAssert(app.staticTexts["Counter: 1"].waitForExistence(timeout: 10))
        app.buttons["+"].tap()
        XCTAssert(app.staticTexts["Counter: 2"].waitForExistence(timeout: 10))
        app.buttons["-"].tap()
        XCTAssert(app.staticTexts["Counter: 1"].waitForExistence(timeout: 10))
    }
}
