package com.example.dex.ui.theme

import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition

/**
 * Configuration object containing the specific physics tuning values ported
 * from the Desktop DeX spatial menu. Centralizing these values allows for
 * easy tweaking across the entire application without hunting for magic numbers.
 */
object SpatialPhysics {
    // Amplitudes
    const val POP_IN_AMPLITUDE = 3.53f
    const val HOVER_AMPLITUDE = 1.22f
    
    // Scales
    const val POP_IN_INITIAL_SCALE = 0.90f
    const val HOVER_EXIT_TARGET_SCALE = 0.96f
    
    // Offsets
    const val POP_IN_INITIAL_OFFSET_Y = 35
    const val HOVER_EXIT_TARGET_OFFSET_Y = 30
    
    // Durations
    const val POP_IN_DURATION_MS = 600
    const val POP_IN_FADE_DURATION_MS = 400
    const val HOVER_EXIT_DURATION_MS = 300
}

/**
 * Creates a bespoke BackEaseOut physics curve (equivalent to WPF's BackEase EaseOut).
 * 
 * @param amplitude The magnitude of the overshoot effect.
 */
fun createBackEaseOut(amplitude: Float): Easing = object : Easing {
    override fun transform(fraction: Float): Float {
        val t = fraction - 1f
        return 1f + t * t * ((amplitude + 1f) * t + amplitude)
    }
}

// Predefined bespoke easing curves
val PopInEase = createBackEaseOut(SpatialPhysics.POP_IN_AMPLITUDE)
val HoverEase = createBackEaseOut(SpatialPhysics.HOVER_AMPLITUDE)

/**
 * Spatial Menu Entrance Transition
 * Starts scaled down and explodes outward with a bounce, along with a parallax slide-up.
 * 
 * @param initialScale The starting scale size before exploding outward.
 * @param initialOffsetY The starting Y-axis parallax slide-up offset.
 * @param animationDuration The time taken for the structural enter animations.
 * @param fadeDuration The time taken specifically for the fade-in.
 * @param easing The physics curve to apply.
 */
fun spatialMenuEnter(
    initialScale: Float = SpatialPhysics.POP_IN_INITIAL_SCALE,
    initialOffsetY: Int = SpatialPhysics.POP_IN_INITIAL_OFFSET_Y,
    animationDuration: Int = SpatialPhysics.POP_IN_DURATION_MS,
    fadeDuration: Int = SpatialPhysics.POP_IN_FADE_DURATION_MS,
    easing: Easing = PopInEase
): EnterTransition {
    return scaleIn(
        initialScale = initialScale,
        animationSpec = tween(durationMillis = animationDuration, easing = easing)
    ) + slideInVertically(
        initialOffsetY = { initialOffsetY },
        animationSpec = tween(durationMillis = animationDuration, easing = easing)
    ) + fadeIn(
        animationSpec = tween(durationMillis = fadeDuration)
    )
}

/**
 * Spatial Menu Exit Transition
 * Subtly slides back out of frame and shrinks slightly.
 * 
 * @param targetScale The shrink size target when exiting.
 * @param targetOffsetY The downward slide exit target offset.
 * @param animationDuration The time taken for the overall exit transition.
 * @param easing The physics curve to apply.
 */
fun spatialMenuExit(
    targetScale: Float = SpatialPhysics.HOVER_EXIT_TARGET_SCALE,
    targetOffsetY: Int = SpatialPhysics.HOVER_EXIT_TARGET_OFFSET_Y,
    animationDuration: Int = SpatialPhysics.HOVER_EXIT_DURATION_MS,
    easing: Easing = HoverEase
): ExitTransition {
    return scaleOut(
        targetScale = targetScale,
        animationSpec = tween(durationMillis = animationDuration, easing = easing)
    ) + slideOutVertically(
        targetOffsetY = { targetOffsetY },
        animationSpec = tween(durationMillis = animationDuration, easing = easing)
    ) + fadeOut(
        animationSpec = tween(durationMillis = animationDuration)
    )
}
