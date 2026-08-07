package com.lookafter.app

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.lookafter.app.health.HealthConnectRepository
import com.lookafter.core.engine.LifeEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.health.HealthSummary
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * Lifecycle bridge from Jetpack Compose → pure [LifeEngine] + platform adapters.
 *
 * - Exposes [state] as a cold-stable [StateFlow] from the engine
 * - Exposes [health] from [HealthConnectRepository]
 * - Forwards [LookAfterIntent]s on [viewModelScope]
 * - Holds zero scheduling physics (all in lookafter-core)
 */
class LookAfterViewModel(
    application: Application,
) : AndroidViewModel(application) {

    private val app = application as LookAfterApplication
    private val engine: LifeEngine = app.lifeEngine
    private val healthRepo: HealthConnectRepository = app.healthRepository

    val state: StateFlow<LifeState> = engine.state
    val health: StateFlow<HealthSummary> = healthRepo.summary
    val healthPermissionGranted: StateFlow<Boolean> = healthRepo.permissionGranted

    fun dispatch(intent: LookAfterIntent) {
        viewModelScope.launch {
            engine.process(intent)
        }
    }

    fun setHealthPermission(granted: Boolean) {
        healthRepo.markPermission(granted)
        viewModelScope.launch { healthRepo.refresh() }
    }

    fun refreshHealth() {
        viewModelScope.launch { healthRepo.refresh() }
    }
}
