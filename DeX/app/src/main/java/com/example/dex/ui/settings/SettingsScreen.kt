package com.example.dex.ui.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.dex.R
import com.example.dex.network.DeviceConfig
import com.example.dex.network.DiscoveryEngine
import com.example.dex.ui.components.DeXGlassPanel
import com.kashif_e.backdrop.Backdrop
import org.koin.compose.koinInject

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    backdrop: Backdrop,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    deviceConfig: DeviceConfig = koinInject(),
    discoveryEngine: DiscoveryEngine = koinInject()
) {
    val emailText by deviceConfig.emailFlow.collectAsState()
    val hashPreview by deviceConfig.identityHashFlow.collectAsState()

    Scaffold(
        containerColor = Color.Transparent,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings_title), fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent,
                    titleContentColor = MaterialTheme.colorScheme.onSurface
                )
            )
        }
    ) { padding ->
        Column(
            modifier = modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            DeXGlassPanel(
                backdrop = backdrop,
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text(
                        stringResource(R.string.trust_identity_title),
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.primary
                    )
                    
                    Text(
                        stringResource(R.string.trust_identity_desc),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
        
                    OutlinedTextField(
                        value = emailText,
                        onValueChange = { 
                            deviceConfig.email = it
                            discoveryEngine.stopDiscovery()
                            discoveryEngine.startDiscovery()
                        },
                        label = { Text(stringResource(R.string.email_address)) },
                        placeholder = { Text(stringResource(R.string.email_placeholder)) },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        colors = OutlinedTextFieldDefaults.colors(
                            unfocusedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f),
                            unfocusedContainerColor = Color.White.copy(alpha = 0.1f),
                            focusedContainerColor = Color.White.copy(alpha = 0.2f)
                        )
                    )
        
                    Spacer(modifier = Modifier.height(8.dp))
        
                    Text(
                        stringResource(R.string.current_identity_hash),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold
                    )
                    
                    Surface(
                        color = Color.Black.copy(alpha = 0.05f),
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            text = hashPreview,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(12.dp)
                        )
                    }
                }
            }
        }
    }
}
