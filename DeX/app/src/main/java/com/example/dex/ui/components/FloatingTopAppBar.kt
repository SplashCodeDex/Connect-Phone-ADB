package com.example.dex.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.res.vectorResource
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.example.dex.R

@Composable
fun FloatingTopAppBar(
    modifier: Modifier = Modifier,
    onOpenTrustedDevices: (() -> Unit)? = null
) {
    var showProfileDialog by remember { mutableStateOf(false) }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 8.dp, start = 16.dp, end = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        // User Avatar
        val avatarInteractionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
        Box(
            modifier = Modifier
                .size(56.dp)
                .bubbleFluidity()
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .border(1.dp, Color.White.copy(alpha = 0.2f), CircleShape)
                .clickable(
                    interactionSource = avatarInteractionSource,
                    indication = LocalIndication.current,
                    onClick = { showProfileDialog = true }
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = ImageVector.vectorResource(R.drawable.ic_account_circle),
                contentDescription = "Profile",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(32.dp)
            )
        }

        // Brand Logo
        Box(
            modifier = Modifier.height(56.dp),
            contentAlignment = Alignment.Center
        ) {
            Image(
                painter = painterResource(id = R.drawable.dex_logo),
                contentDescription = "DeX Logo",
                modifier = Modifier.fillMaxHeight(),
                contentScale = ContentScale.Fit
            )
        }

        // Action Buttons Group
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (onOpenTrustedDevices != null) {
                val devicesInteractionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
                Box(
                    modifier = Modifier
                        .size(56.dp)
                        .bubbleFluidity()
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.4f))
                        .border(1.dp, Color.White.copy(alpha = 0.2f), CircleShape)
                        .clickable(
                            interactionSource = devicesInteractionSource,
                            indication = LocalIndication.current,
                            onClick = { onOpenTrustedDevices() }
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = ImageVector.vectorResource(R.drawable.ic_devices_filled),
                        contentDescription = "Trusted Devices",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(28.dp)
                    )
                }
            }

            // Search Button
            val searchInteractionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
            Box(
                modifier = Modifier
                    .size(56.dp)
                    // Apply physics BEFORE drawing background/borders so the whole button scales
                    .bubbleFluidity()
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.4f))
                    .border(1.dp, Color.White.copy(alpha = 0.2f), CircleShape)
                    .clickable(
                        interactionSource = searchInteractionSource,
                        indication = LocalIndication.current,
                        onClick = { /* Search action placeholder */ }
                    ),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = ImageVector.vectorResource(R.drawable.ic_search),
                    contentDescription = "Search",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(32.dp)
                )
            }
        }
    }

    if (showProfileDialog) {
        AlertDialog(
            onDismissRequest = { showProfileDialog = false },
            title = { Text(text = "Profile") },
            text = { Text(text = "This is a placeholder for the user profile functionality. Account integration coming soon!") },
            confirmButton = {
                DeXTextButton(onClick = { showProfileDialog = false }) {
                    Text("OK")
                }
            }
        )
    }
}
