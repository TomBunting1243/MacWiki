import AppKit
import Testing

@testable import MacWiki

@MainActor
struct SettingsControlBehaviorTests {
    @Test func accessibilityAdjustmentsHonorTheDeclaredSliderStep() {
        let slider = ExactStepSettingsSlider(
            value: 430,
            minValue: 420,
            maxValue: 1_400,
            target: nil,
            action: nil
        )
        slider.accessibilityStep = 10

        #expect(slider.accessibilityPerformIncrement())
        #expect(slider.doubleValue == 440)
        #expect(slider.accessibilityPerformDecrement())
        #expect(slider.doubleValue == 430)
    }

    @Test func accessibilityAdjustmentsStopAtSliderBounds() {
        let slider = ExactStepSettingsSlider(
            value: 30,
            minValue: 13,
            maxValue: 30,
            target: nil,
            action: nil
        )
        slider.accessibilityStep = 1

        #expect(!slider.accessibilityPerformIncrement())
        #expect(slider.doubleValue == 30)
        #expect(slider.accessibilityPerformDecrement())
        #expect(slider.doubleValue == 29)
    }

    @Test func accessibleActionButtonConfigurationUsesNativeSemantics() {
        var invocationCount = 0
        let control = AccessibleActionButton(
            "Delete All Data",
            isDestructive: true,
            isEnabled: false,
            keyEquivalent: "d"
        ) {
            invocationCount += 1
        }
        let coordinator = control.makeCoordinator()
        let button = NSButton()

        control.configure(button, coordinator: coordinator)

        #expect(button.title == "Delete All Data")
        #expect(button.hasDestructiveAction)
        #expect(!button.isEnabled)
        #expect(button.keyEquivalent == "d")
        #expect(button.accessibilityRole() == .button)
        #expect(button.accessibilityLabel() == "Delete All Data")

        coordinator.performAction()
        #expect(invocationCount == 1)
    }
}
