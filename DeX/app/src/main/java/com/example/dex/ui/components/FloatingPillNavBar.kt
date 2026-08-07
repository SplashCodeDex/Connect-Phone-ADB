package com.example.dex.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.kashif_e.backdrop.Backdrop

data class NavBarItem(
    val icon: ImageVector,
    val contentDescription: String,
    val isSelected: Boolean,
    val onClick: () -> Unit
)

@Composable
fun FloatingPillNavBar(
    backdrop: Backdrop,
    items: List<NavBarItem>,
    modifier: Modifier = Modifier
) {
    DeXGlassPanel(
        backdrop = backdrop,
        shape = RoundedCornerShape(100.dp),
        blurRadius = 8.dp,
        modifier = modifier
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically
        ) {
        items.forEach { item ->
            NavBarIcon(item = item)
        }
        }
    }
}

@Composable
private fun NavBarIcon(item: NavBarItem) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    
    val scale by animateFloatAsState(
        targetValue = if (isPressed) 0.85f else 1f,
        label = "scale"
    )

    val tint = if (item.isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
    val bgAlpha = if (item.isSelected) 0.15f else 0f

    Box(
        modifier = Modifier
            .scale(scale)
            .clip(CircleShape)
            .clickable(
                interactionSource = interactionSource,
                indication = null, 
                onClick = item.onClick
            )
            .background(tint.copy(alpha = bgAlpha))
            .padding(12.dp),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = item.icon,
            contentDescription = item.contentDescription,
            tint = tint,
            modifier = Modifier.size(26.dp)
        )
    }
}
