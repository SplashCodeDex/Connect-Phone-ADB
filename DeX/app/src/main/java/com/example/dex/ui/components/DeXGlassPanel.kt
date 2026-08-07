package com.example.dex.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.kashif_e.backdrop.Backdrop
import com.kashif_e.backdrop.drawBackdrop
import com.kashif_e.backdrop.effects.blur
import com.kashif_e.backdrop.effects.colorControls
import com.kashif_e.backdrop.effects.lens
import com.kashif_e.backdrop.effects.vibrancy
import com.kashif_e.backdrop.highlight.Highlight
import com.kashif_e.backdrop.shadow.Shadow

@Composable
fun DeXGlassPanel(
    backdrop: Backdrop,
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(24.dp),
    blurRadius: Dp = 12.dp,
    lensRadius: Dp = 16.dp,
    lensDisplacement: Dp = 24.dp,
    shadowRadius: Dp = 12.dp,
    darken: Boolean = false,
    content: @Composable BoxScope.() -> Unit
) {
    Box(
        modifier = modifier.drawBackdrop(
            backdrop = backdrop,
            shape = { shape },
            effects = {
                if (darken) {
                    colorControls(brightness = 0.2f, saturation = 1.2f)
                } else {
                    vibrancy()
                }
                blur(blurRadius.toPx())
                lens(lensRadius.toPx(), lensDisplacement.toPx())
            },
            highlight = { if (darken) Highlight.Plain else Highlight.Default },
            shadow = { Shadow(radius = shadowRadius, color = Color.Black.copy(0.15f)) },
            onDrawSurface = { drawRect(Color.White.copy(alpha = 0.15f)) }
        ),
        content = content
    )
}
