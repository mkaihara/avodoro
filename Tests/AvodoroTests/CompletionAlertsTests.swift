import Testing
@testable import Avodoro

struct CompletionAlertsTests {
    @Test func focusWithTask() {
        let text = NotificationText.make(type: .focus, description: "Write blog\npost  #writing ")
        #expect(text.title == "Focus session done")
        #expect(text.body == "Write blog post #writing")
    }

    @Test func focusUntitled() {
        #expect(NotificationText.make(type: .focus, description: "  ") == ("Focus session done", "Time for a break."))
    }

    @Test func breakIsOver() {
        #expect(NotificationText.make(type: .break, description: "anything") == ("Break is over", "Ready to focus?"))
    }
}
