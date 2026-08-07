package com.lookafter.app.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.lookafter.app.ui.components.LookAfterBottomNav
import com.lookafter.app.ui.navigation.AppDestination
import com.lookafter.app.ui.theme.LookAfterTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Instrumentation smoke — bottom nav labels + capture affordance.
 * Requires device/emulator; skipped on plain unit-test CI job.
 */
@RunWith(AndroidJUnit4::class)
class BottomNavSmokeTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun showsFourTabsAndCapture() {
        var selected = AppDestination.TODAY
        var captureClicks = 0
        composeRule.setContent {
            LookAfterTheme {
                LookAfterBottomNav(
                    current = selected,
                    onSelect = { selected = it },
                    onCapture = { captureClicks++ },
                )
            }
        }
        composeRule.onNodeWithText("Briefing").assertIsDisplayed()
        composeRule.onNodeWithText("Today").assertIsDisplayed()
        composeRule.onNodeWithText("Brain").assertIsDisplayed()
        composeRule.onNodeWithText("You").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("Capture").assertIsDisplayed().performClick()
        composeRule.runOnIdle {
            assert(captureClicks == 1)
        }
    }
}
