package com.example.dex.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import kotlinx.coroutines.launch

/**
 * Applies a "bubble fluidity" physics effect.
 * When touched, the component scales down (squishes).
 * When swiped/dragged, the component slightly pulls towards the finger.
 * When released, it bounces back with high elasticity.
 * 
 * @param targetScale The scale to squish down to on press.
 * @param pullFactor How much the bubble pulls towards the finger (0.0 to 1.0).
 */
fun Modifier.bubbleFluidity(
    targetScale: Float = 0.85f,
    pullFactor: Float = 0.2f
): Modifier = composed {
    val scale = remember { Animatable(1f) }
    val translationX = remember { Animatable(0f) }
    val translationY = remember { Animatable(0f) }
    
    val coroutineScope = rememberCoroutineScope()
    
    this
        .graphicsLayer {
            scaleX = scale.value
            scaleY = scale.value
            this.translationX = translationX.value
            this.translationY = translationY.value
        }
        .pointerInput(Unit) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                
                // On Press: Shrink and squish (Liquid compression)
                coroutineScope.launch {
                    scale.animateTo(
                        targetValue = targetScale,
                        animationSpec = spring(
                            dampingRatio = Spring.DampingRatioMediumBouncy,
                            stiffness = Spring.StiffnessLow
                        )
                    )
                }
                
                // Track drag/swipe without consuming so clickable still works
                var pointerEvent = awaitPointerEvent()
                while (pointerEvent.changes.any { it.pressed }) {
                    val change = pointerEvent.changes.first()
                    val position = change.position
                    
                    // Calculate offset from center of the component
                    val offsetX = position.x - size.width / 2f
                    val offsetY = position.y - size.height / 2f
                    
                    // Pull effect
                    coroutineScope.launch {
                        translationX.animateTo(
                            targetValue = offsetX * pullFactor,
                            animationSpec = spring(stiffness = Spring.StiffnessMedium)
                        )
                        translationY.animateTo(
                            targetValue = offsetY * pullFactor,
                            animationSpec = spring(stiffness = Spring.StiffnessMedium)
                        )
                    }
                    
                    pointerEvent = awaitPointerEvent()
                }
                
                // On Release: Elastic bounce back
                coroutineScope.launch {
                    launch {
                        scale.animateTo(
                            targetValue = 1f,
                            animationSpec = spring(
                                dampingRatio = Spring.DampingRatioHighBouncy,
                                stiffness = Spring.StiffnessMedium
                            )
                        )
                    }
                    launch {
                        translationX.animateTo(
                            targetValue = 0f,
                            animationSpec = spring(
                                dampingRatio = Spring.DampingRatioHighBouncy,
                                stiffness = Spring.StiffnessMedium
                            )
                        )
                    }
                    launch {
                        translationY.animateTo(
                            targetValue = 0f,
                            animationSpec = spring(
                                dampingRatio = Spring.DampingRatioHighBouncy,
                                stiffness = Spring.StiffnessMedium
                            )
                        )
                    }
                }
            }
        }
}
