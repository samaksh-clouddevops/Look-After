package com.lookafter.core.medication

import com.lookafter.core.models.Medication
import java.time.LocalTime
import kotlin.test.Test
import kotlin.test.assertTrue

class MedicationPromptBuilderTest {

    @Test
    fun emptyPromptBlock() {
        val block = MedicationPromptBuilder.promptBlock(emptyList())
        assertTrue(block.contains("none configured"))
    }

    @Test
    fun emptySafetyRules() {
        val rules = MedicationPromptBuilder.medicalSafetyRulesBlock(emptyList())
        assertTrue(rules.lowercase().contains("no medications"))
    }

    @Test
    fun configuredMedsAppearInBlocks() {
        val med = Medication(
            id = "m1",
            name = "Adderall",
            dosage = "20mg",
            scheduledTime = LocalTime.of(8, 0),
            isTaken = false,
        )
        val prompt = MedicationPromptBuilder.promptBlock(listOf(med))
        assertTrue(prompt.contains("Adderall"))
        assertTrue(prompt.contains("m1"))
        assertTrue(prompt.contains("due"))

        val rules = MedicationPromptBuilder.medicalSafetyRulesBlock(listOf(med))
        assertTrue(rules.contains("Adderall"))
        assertTrue(rules.contains("medicalRisk"))
    }
}
