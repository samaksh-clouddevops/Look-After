package com.lookafter.app.ui.modules

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.components.CalmEmptyState
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.modules.AppModule
import com.lookafter.core.modules.AppModuleCatalog
import com.lookafter.core.modules.ModuleDestination
import com.lookafter.core.modules.ModuleStatus

/**
 * Modules grid launcher (Phase E0) — discover shipped & coming-soon features.
 */
@Composable
fun ModulesScreen(
    onOpen: (ModuleDestination) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    modules: List<AppModule> = AppModuleCatalog.all,
) {
    var query by remember { mutableStateOf("") }
    val filtered = remember(query, modules) {
        if (query.isBlank()) modules
        else AppModuleCatalog.search(query).filter { m -> modules.any { it.id == m.id } }
    }
    val groups = remember(filtered) {
        com.lookafter.core.modules.ModuleGroup.entries.mapNotNull { g ->
            val items = filtered.filter { it.group == g }
            if (items.isEmpty()) null else g to items
        }
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = LookAfterDimens.screenHorizontal,
            vertical = LookAfterDimens.spacingLG,
        ),
        verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingMD),
    ) {
        item {
            SectionHeader(
                title = "Modules",
                subtitle = "Everything Look After can hold — open what’s ready.",
            )
        }
        item {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                label = { Text("Search modules") },
            )
        }
        if (groups.isEmpty()) {
            item {
                CalmEmptyState(
                    title = "No matches",
                    subtitle = "Try another search, or clear the field.",
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 24.dp),
                )
            }
        } else {
            groups.forEach { (group, items) ->
                item(key = "g-${group.name}") {
                    Text(
                        group.title,
                        style = MaterialTheme.typography.titleMedium,
                        color = LookAfterColors.AccentPrimary,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                    )
                }
                items(items.chunked(2), key = { row -> row.joinToString("-") { it.id } }) { row ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
                    ) {
                        row.forEach { mod ->
                            ModuleCard(
                                module = mod,
                                onClick = {
                                    if (mod.isOpenable) onOpen(mod.destination)
                                },
                                modifier = Modifier.weight(1f),
                            )
                        }
                        if (row.size == 1) {
                            SpacerWeight(Modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        }
        item {
            Text(
                "Back",
                color = LookAfterColors.AccentPrimary,
                modifier = Modifier
                    .clickable(onClick = onBack)
                    .padding(top = LookAfterDimens.spacingSM),
            )
        }
    }
}

@Composable
private fun SpacerWeight(modifier: Modifier = Modifier) {
    // empty flex cell for odd rows
    Column(modifier = modifier.height(1.dp)) {}
}

@Composable
private fun ModuleCard(
    module: AppModule,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val enabled = module.isOpenable
    ElevatedSurfaceCard(
        modifier = modifier
            .then(if (enabled) Modifier.clickable(onClick = onClick) else Modifier),
    ) {
        Text(
            module.status.label,
            style = MaterialTheme.typography.labelMedium,
            color = when (module.status) {
                ModuleStatus.SHIPPED -> LookAfterColors.AccentPrimary
                ModuleStatus.BETA -> LookAfterColors.Focus
                ModuleStatus.COMING_SOON -> MaterialTheme.colorScheme.onSurfaceVariant
            },
        )
        Text(
            module.title,
            style = MaterialTheme.typography.titleLarge,
            color = if (enabled) {
                MaterialTheme.colorScheme.onSurface
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
            modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
        )
        Text(
            module.subtitle,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
        )
    }
}
