package com.lookafter.app

import android.app.Application
import com.lookafter.core.engine.LifeEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * Process-scoped application shell.
 *
 * Owns the pure [LifeEngine] singleton so ViewModels can share one universe.
 * Phase-3 seeds a tiny demo schedule so the Compose proof UI has tasks to sweep.
 */
class LookAfterApplication : Application() {

    lateinit var lifeEngine: LifeEngine
        private set

    override fun onCreate() {
        super.onCreate()
        lifeEngine = LifeEngine(initialState = demoState())
    }

    private fun demoState(): LifeState {
        val zone = ZoneOffset.UTC
        val yesterday = LocalDate.now(zone).minusDays(1)
        val meal = LifeTask(
            id = "demo-dinner",
            title = "Dinner (EndOfDay)",
            durationMinutes = 45,
            constraintType = ConstraintType.FLEXIBLE,
            status = TaskStatus.PENDING,
            expirationPolicy = TaskExpirationPolicy.EndOfDay,
            scheduledDate = yesterday,
            scheduledStart = yesterday.atTime(19, 0).atZone(zone).toInstant(),
            scheduledEnd = yesterday.atTime(19, 45).atZone(zone).toInstant(),
        )
        val work = LifeTask(
            id = "demo-deep-work",
            title = "Deep work draft",
            durationMinutes = 90,
            constraintType = ConstraintType.FLEXIBLE,
            status = TaskStatus.PENDING,
            expirationPolicy = TaskExpirationPolicy.Infinite,
            scheduledDate = yesterday,
            scheduledStart = yesterday.atTime(14, 0).atZone(zone).toInstant(),
        )
        return LifeState(
            activeTasks = listOf(meal, work),
            currentDay = yesterday,
        )
    }
}
