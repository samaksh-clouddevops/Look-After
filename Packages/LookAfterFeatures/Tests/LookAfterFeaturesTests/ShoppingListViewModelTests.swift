import XCTest
@testable import LookAfterFeatures
import LookAfterCore
import LookAfterData

final class ShoppingListViewModelTests: XCTestCase {

    @MainActor
    func testAddShoppingItemRejectsEmptyName() async {
        let vm = LifeModulesViewModel(shoppingRepo: ShoppingRepository())
        let success = await vm.addShoppingItem(name: "   ", category: "General")
        XCTAssertFalse(success)
        XCTAssertEqual(vm.error, "Enter an item name before creating.")
    }

    @MainActor
    func testAddShoppingItemPersistsLocally() async {
        let repo = ShoppingRepository()
        let vm = LifeModulesViewModel(shoppingRepo: repo)

        let success = await vm.addShoppingItem(name: "Almond milk", category: "Groceries")
        XCTAssertTrue(success)
        XCTAssertEqual(vm.shoppingItems.first?.name, "Almond milk")
        XCTAssertEqual(vm.shoppingSuccessMessage, "\"Almond milk\" added to your list")
        XCTAssertFalse(vm.isAddingShoppingItem)
    }

    @MainActor
    func testIsAddingShoppingItemResetsAfterFailure() async {
        let vm = LifeModulesViewModel(shoppingRepo: ShoppingRepository())
        _ = await vm.addShoppingItem(name: "   ", category: "General")
        XCTAssertFalse(vm.isAddingShoppingItem)
    }
}
