package com.lookafter.core.medication

import com.lookafter.core.models.Medication
import java.time.format.DateTimeFormatter

/**
 * Pure prompt helpers for the medication domain — mirrors iOS MedicationPromptBuilder.
 * Inventory lives in LifeState; this never loads from disk.
 */
object MedicationPromptBuilder {

    private val timeFmt: DateTimeFormatter = DateTimeFormatter.ofPattern("h:mm a")

    fun promptBlock(medications: List<Medication>, limit: Int = 12): String {
        val meds = medications.take(limit)
        if (meds.isEmpty()) return "- none configured"
        return meds.joinToString("\n") { med ->
            val taken = if (med.isTaken) "taken" else "due"
            val time = med.scheduledTime.format(timeFmt)
            "- id:${med.id} | ${med.name} | $time | $taken"
        }
    }

    fun medicalSafetyRulesBlock(medications: List<Medication>): String {
        if (medications.isEmpty()) {
            return """
                - No medications configured — classify medication tasks only when title/description clearly indicates meds.
                - Never invent evening medication timing unless explicitly stated in the task.
            """.trimIndent()
        }
        val lines = mutableListOf(
            "CONFIGURED MEDICATIONS (mandatory — use these schedules, never invent times):",
        )
        for (med in medications) {
            lines += "- ${med.name}: scheduled ${med.scheduledTime.format(timeFmt)}"
        }
        lines += "- Match task titles to configured meds when relevant."
        lines += "- consequenceOfDelay=medicalRisk for time-sensitive medications."
        lines += "- Never invent evening doses unless explicitly in the task title."
        return lines.joinToString("\n")
    }
}
