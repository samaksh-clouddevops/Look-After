package com.lookafter.core.modules

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class AppModuleCatalogTest {

    @Test
    fun catalogHasShippedAndComingSoon() {
        assertTrue(AppModuleCatalog.openable().isNotEmpty())
        assertTrue(AppModuleCatalog.comingSoon().isNotEmpty())
        assertTrue(AppModuleCatalog.all.any { it.id == "today" && it.isOpenable })
        assertTrue(AppModuleCatalog.all.any { it.id == "travel" && it.isOpenable })
        assertTrue(AppModuleCatalog.all.any { it.id == "cycle" && !it.isOpenable })
    }

    @Test
    fun groupedCoversEveryModuleOnce() {
        val grouped = AppModuleCatalog.grouped()
        assertTrue(grouped.isNotEmpty())
        val ids = grouped.flatMap { it.second }.map { it.id }
        assertEquals(AppModuleCatalog.all.size, ids.distinct().size)
    }

    @Test
    fun searchFindsHealthAndFiltersMisses() {
        val hits = AppModuleCatalog.search("health")
        assertTrue(hits.any { it.id == "health" })
        assertTrue(AppModuleCatalog.search("zzzz-nope").isEmpty())
    }

    @Test
    fun companionIsBetaOpenable() {
        val c = AppModuleCatalog.byId("companion")
        assertEquals(ModuleStatus.BETA, c?.status)
        assertTrue(c?.isOpenable == true)
    }
}
