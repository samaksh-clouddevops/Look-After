package com.lookafter.app

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.lookafter.core.engine.LifeEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * Lifecycle bridge from Jetpack Compose → pure [LifeEngine].
 *
 * - Exposes [state] as a cold-stable [StateFlow] from the engine
 * - Forwards [LookAfterIntent]s on [viewModelScope]
 * - Holds zero scheduling physics (all in lookafter-core)
 */
class LookAfterViewModel(
    application: Application,
) : AndroidViewModel(application) {

    private val engine: LifeEngine =
        (application as LookAfterApplication).lifeEngine

    val state: StateFlow<LifeState> = engine.state

    fun dispatch(intent: LookAfterIntent) {
        viewModelScope.launch {
            engine.process(intent)
        }
    }
}
