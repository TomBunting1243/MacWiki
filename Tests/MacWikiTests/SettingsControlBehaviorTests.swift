import AppKit
import SwiftUI
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

    @Test func accessibleSettingsToggleUsesNativeTitleValueAndIdentifier() {
        var isOn = true
        let binding = Binding(
            get: { isOn },
            set: { isOn = $0 }
        )
        let control = AccessibleSettingsToggle(
            "Hide Sidebar Time Machine",
            isOn: binding,
            identifier: "settings.navigation.hideSidebarTimeMachine"
        )
        let coordinator = control.makeCoordinator()
        let button = NSButton()

        control.configure(button, coordinator: coordinator)

        #expect(button.title == "Hide Sidebar Time Machine")
        #expect(button.state == .on)
        #expect(button.identifier?.rawValue == "settings.navigation.hideSidebarTimeMachine")
        #expect(button.accessibilityRole() == .checkBox)
        #expect(button.accessibilityTitle() == "Hide Sidebar Time Machine")
        #expect(button.accessibilityLabel() == "Hide Sidebar Time Machine")

        button.state = .off
        coordinator.valueChanged(button)
        #expect(!isOn)
    }
}
