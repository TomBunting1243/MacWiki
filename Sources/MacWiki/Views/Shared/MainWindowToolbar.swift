import SwiftUI

struct MainWindowToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            MainWindowCommandBar()
        }
    }
}
