package com.lookafter.core.onboarding

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class OnboardingEngineTest {

    @Test
    fun advancesThroughStepsThenDone() {
        var s = OnboardingState.fresh
        s = OnboardingEngine.reduce(s, OnboardingIntent.SetName("Sam"))
        assertEquals("Sam", s.displayName)
        s = OnboardingEngine.reduce(s, OnboardingIntent.Next)
        assertEquals(OnboardingStep.CAPTURE_INTENT, s.step)
        s = OnboardingEngine.reduce(s, OnboardingIntent.Next)
        assertEquals(OnboardingStep.HEALTH_PERMISSION, s.step)
        s = OnboardingEngine.reduce(s, OnboardingIntent.Next)
        assertEquals(OnboardingStep.MEDICATION_INTRO, s.step)
        s = OnboardingEngine.reduce(s, OnboardingIntent.Next)
        assertEquals(OnboardingStep.DONE, s.step)
        assertTrue(s.completed)
    }

    @Test
    fun skipCompletes() {
        val s = OnboardingEngine.reduce(OnboardingState.fresh, OnboardingIntent.Skip)
        assertTrue(s.completed)
        assertEquals(OnboardingStep.DONE, s.step)
    }

    @Test
    fun resetReturnsFresh() {
        val s = OnboardingEngine.reduce(OnboardingState.done, OnboardingIntent.Reset)
        assertFalse(s.completed)
        assertEquals(OnboardingStep.WELCOME, s.step)
    }
}
