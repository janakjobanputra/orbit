import XCTest
@testable import Orbit

final class HelpTopicsTests: XCTestCase {

    func testEveryGroupHasQuestionsAndEveryQuestionIsUnique() {
        for group in HelpTopic.Group.allCases {
            XCTAssertFalse(HelpTopic.topics(in: group).isEmpty, group.rawValue)
        }
        XCTAssertEqual(Set(HelpTopic.all.map(\.question)).count, HelpTopic.all.count)
    }

    func testAnswersArentEmptyAndQuestionsReadAsQuestions() {
        for topic in HelpTopic.all {
            XCTAssertFalse(topic.answer.isEmpty, topic.question)
            XCTAssertTrue(topic.question.hasSuffix("?") || topic.question.hasSuffix("."), topic.question)
        }
    }

    func testCoversTheMenuBarClockAndMovingItems() {
        let questions = HelpTopic.topics(in: .menuBar).map(\.question)
        XCTAssertTrue(questions.contains { $0.contains("date and time") })
        XCTAssertTrue(questions.contains { $0.contains("move Orbit") })
    }
}
