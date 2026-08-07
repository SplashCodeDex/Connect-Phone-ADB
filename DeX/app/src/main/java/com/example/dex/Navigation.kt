package com.example.dex

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import com.example.dex.ui.components.FloatingPillNavBar
import com.example.dex.ui.components.NavBarItem
import com.example.dex.ui.main.MainScreen
import com.example.dex.ui.settings.SettingsScreen
import com.kashif_e.backdrop.backdrops.rememberLayerBackdrop
import com.kashif_e.backdrop.backdrops.layerBackdrop

@Composable
fun MainNavigation() {
  val backStack = rememberNavBackStack(Main)
  val backdrop = rememberLayerBackdrop()
  val currentRoute = backStack.lastOrNull()

  val navItems = remember(currentRoute) {
    listOf(
      NavBarItem(
        icon = Icons.Rounded.Home,
        contentDescription = "Home",
        isSelected = currentRoute == Main,
        onClick = { 
          if (currentRoute != Main) {
            backStack.clear()
            backStack.add(Main)
          }
        }
      ),
      NavBarItem(
        icon = Icons.Rounded.Settings,
        contentDescription = "Settings",
        isSelected = currentRoute == Settings,
        onClick = {
          if (currentRoute != Settings) {
            backStack.add(Settings)
          }
        }
      )
    )
  }

  Box(modifier = Modifier.fillMaxSize()) {
    // Background layer that provides the source for the backdrop effects
    Box(
      modifier = Modifier
        .fillMaxSize()
        .background(androidx.compose.ui.graphics.Color.Black)
        .layerBackdrop(backdrop)
    )

    NavDisplay(
      backStack = backStack,
      onBack = { backStack.removeLastOrNull() },
      modifier = Modifier,
      entryProvider =
        entryProvider {
          entry<Main> {
            MainScreen(
              backdrop = backdrop,
              modifier = Modifier.safeDrawingPadding().padding(16.dp)
            )
          }
          entry<Settings> {
            SettingsScreen(
              backdrop = backdrop,
              onBack = { backStack.removeLastOrNull() },
              modifier = Modifier.safeDrawingPadding()
            )
          }
        },
    )
    
    FloatingPillNavBar(
      backdrop = backdrop,
      items = navItems,
      modifier = Modifier
        .align(Alignment.BottomCenter)
        .safeDrawingPadding()
        .padding(bottom = 24.dp)
    )
  }
}
