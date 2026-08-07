package com.lookafter.core.onboarding

import kotlinx.serialization.Serializable

@Serializable
enum class OnboardingStep {
    WELCOME,
    CAPTURE_INTENT,
    HEALTH_PERMISSION,
    MEDICATION_INTRO,
    DONE,
}

@Serializable
data class OnboardingState(
    val step: OnboardingStep = OnboardingStep.WELCOME,
    val completed: Boolean = false,
    val displayName: String = "",
) {
    companion object {
        val fresh = OnboardingState()
        val done = OnboardingState(step = OnboardingStep.DONE, completed = true)
    }
}

sealed class OnboardingIntent {
    data class SetName(val name: String) : OnboardingIntent()
    data object Next : OnboardingIntent()
    data object Skip : OnboardingIntent()
    data object Complete : OnboardingIntent()
    data object Reset : OnboardingIntent()
}

object OnboardingEngine {
    private val order = listOf(
        OnboardingStep.WELCOME,
        OnboardingStep.CAPTURE_INTENT,
        OnboardingStep.HEALTH_PERMISSION,
        OnboardingStep.MEDICATION_INTRO,
        OnboardingStep.DONE,
    )

    fun reduce(current: OnboardingState, intent: OnboardingIntent): OnboardingState = when (intent) {
        is OnboardingIntent.SetName -> current.copy(displayName = intent.name.trim())
        OnboardingIntent.Next -> advance(current)
        OnboardingIntent.Skip, OnboardingIntent.Complete -> OnboardingState.done.copy(
            displayName = current.displayName,
        )
        OnboardingIntent.Reset -> OnboardingState.fresh
    }

    private fun advance(current: OnboardingState): OnboardingState {
        if (current.completed || current.step == OnboardingStep.DONE) {
            return current.copy(completed = true, step = OnboardingStep.DONE)
        }
        val idx = order.indexOf(current.step).coerceAtLeast(0)
        val next = order.getOrElse(idx + 1) { OnboardingStep.DONE }
        return current.copy(
            step = next,
            completed = next == OnboardingStep.DONE,
        )
    }
}
