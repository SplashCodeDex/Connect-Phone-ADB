package com.example.dex

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.FolderShared
import androidx.compose.material.icons.rounded.Devices
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import com.example.dex.ui.components.FloatingPillNavBar
import com.example.dex.ui.components.NavBarItem
import com.example.dex.ui.files.FilesScreen
import com.example.dex.ui.main.MainScreen
import com.example.dex.ui.settings.SettingsScreen

@Composable
fun MainNavigation() {
  val backStack = rememberNavBackStack(Main)
  val currentRoute = backStack.lastOrNull()

  val navItems = remember(currentRoute) {
    listOf(
      NavBarItem(
        icon = Icons.Rounded.Devices,
        contentDescription = "Devices",
        isSelected = currentRoute == Main,
        onClick = { 
          if (currentRoute != Main) {
            backStack.clear()
            backStack.add(Main)
          }
        }
      ),
      NavBarItem(
        icon = Icons.Rounded.FolderShared,
        contentDescription = "Files",
        isSelected = currentRoute == Files,
        onClick = {
          if (currentRoute != Files) {
            backStack.add(Files)
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

  Box(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
    NavDisplay(
      backStack = backStack,
      onBack = { backStack.removeLastOrNull() },
      modifier = Modifier,
      transitionSpec = {
        fadeIn(animationSpec = tween(250)) togetherWith fadeOut(animationSpec = tween(250))
      },
      entryProvider =
        entryProvider {
          entry<Main> {
            MainScreen(
              modifier = Modifier.safeDrawingPadding()
            )
          }
          entry<Files> {
            FilesScreen(
              modifier = Modifier.safeDrawingPadding()
            )
          }
          entry<Settings> {
            SettingsScreen(
              onBack = { backStack.removeLastOrNull() },
              modifier = Modifier.safeDrawingPadding()
            )
          }
        },
    )
    
    FloatingPillNavBar(
      items = navItems,
      modifier = Modifier
        .align(Alignment.BottomCenter)
        .safeDrawingPadding()
        .padding(bottom = 16.dp)
    )
  }
}
