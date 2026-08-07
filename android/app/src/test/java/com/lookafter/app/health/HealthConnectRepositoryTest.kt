package com.lookafter.app.health

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

class HealthConnectRepositoryTest {

    @Test
    fun refreshWithoutPermissionYieldsEmpty() = runTest {
        val repo = HealthConnectRepository()
        val summary = repo.refresh(Instant.parse("2026-08-07T12:00:00Z"))
        assertNull(summary.readinessScore)
        assertEquals("Unknown", summary.readinessLabel)
        assertEquals(false, repo.permissionGranted.value)
    }

    @Test
    fun refreshWithPermissionYieldsDemoReadiness() = runTest {
        val repo = HealthConnectRepository()
        repo.markPermission(true)
        val summary = repo.refresh(Instant.parse("2026-08-07T12:00:00Z"))
        assertTrue(summary.readinessScore != null && summary.readinessScore!! > 0.5)
        assertEquals("Good", summary.readinessLabel)
        assertTrue((summary.totalSleepMinutes ?: 0.0) > 0.0)
        assertEquals(summary, repo.summary.value)
    }

    @Test
    fun revokingPermissionClearsOnRefresh() = runTest {
        val repo = HealthConnectRepository()
        repo.markPermission(true)
        repo.refresh()
        assertTrue(repo.summary.value.readinessScore != null)
        repo.markPermission(false)
        repo.refresh()
        assertNull(repo.summary.value.readinessScore)
    }
}
