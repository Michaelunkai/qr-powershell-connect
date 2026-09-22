// SPDX-License-Identifier: Apache-2.0
package org.connectbot.bridge

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.connectbot.R
import androidx.compose.ui.res.stringResource
import org.connectbot.service.ModifierLevel
import org.connectbot.service.TerminalBridge
import org.connectbot.service.TerminalKeyListener
import org.connectbot.terminal.VTermKey

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RowScope.TouchKey(label: String, description: String = label, active: ModifierLevel = ModifierLevel.OFF, longPress: (() -> Unit)? = null, press: () -> Unit) {
    Box(Modifier.weight(1f).height(52.dp).padding(2.dp)
        .background(if (active == ModifierLevel.OFF) Color(0xFF1A2B42) else Color(0xFF176E79), RoundedCornerShape(8.dp))
        .semantics { contentDescription = description + when (active) { ModifierLevel.TRANSIENT -> ", next key"; ModifierLevel.LOCKED -> ", locked"; else -> "" } }
        .combinedClickable(onClick = press, onLongClick = longPress), contentAlignment = Alignment.Center) {
        Text(label + if (active == ModifierLevel.LOCKED) " •" else "", fontSize = 13.sp, color = Color(0xFFE6F1FF), maxLines = 1)
    }
}

@Composable
fun BridgeKeyboard(bridge: TerminalBridge, imeVisible: Boolean, showIme: () -> Unit, hideIme: () -> Unit, interaction: () -> Unit, shortcutChanged: () -> Unit, modifier: Modifier = Modifier) {
    val handler = bridge.keyHandler
    val state by handler.modifierState.collectAsState()
    var expanded by remember { mutableStateOf(false) }
    fun press(key: Int) { handler.sendPressedKey(key); interaction(); shortcutChanged() }
    fun change(code: Int, level: ModifierLevel, lock: Boolean = false) {
        if (lock) {
            if (level == ModifierLevel.OFF) { handler.metaPress(code, true); handler.metaPress(code, true) }
            else if (level == ModifierLevel.TRANSIENT) handler.metaPress(code, true)
        } else {
            handler.metaPress(code, true)
            if (level == ModifierLevel.TRANSIENT) handler.metaPress(code, true)
        }
        interaction(); shortcutChanged()
    }
    Column(modifier.fillMaxWidth().background(Color(0xFF0D192B)).padding(horizontal = 4.dp)) {
        Row(Modifier.fillMaxWidth()) {
            TouchKey("Esc") { press(VTermKey.ESCAPE) }
            TouchKey("Tab") { press(VTermKey.TAB) }
            TouchKey("Ctrl", active = state.ctrlState, longPress = { change(TerminalKeyListener.CTRL_ON, state.ctrlState, true) }) { change(TerminalKeyListener.CTRL_ON, state.ctrlState) }
            TouchKey("Alt", active = state.altState, longPress = { change(TerminalKeyListener.ALT_ON, state.altState, true) }) { change(TerminalKeyListener.ALT_ON, state.altState) }
            TouchKey("Shift", active = state.shiftState, longPress = { change(TerminalKeyListener.SHIFT_ON, state.shiftState, true) }) { change(TerminalKeyListener.SHIFT_ON, state.shiftState) }
            TouchKey("⌨", stringResource(R.string.bridge_toggle_keyboard)) { if (imeVisible) hideIme() else showIme(); interaction() }
        }
        Row(Modifier.fillMaxWidth()) {
            TouchKey("←", "Left") { press(VTermKey.LEFT) }
            TouchKey("↓", "Down") { press(VTermKey.DOWN) }
            TouchKey("↑", "Up") { press(VTermKey.UP) }
            TouchKey("→", "Right") { press(VTermKey.RIGHT) }
            TouchKey("Home") { press(VTermKey.HOME) }
            TouchKey("End") { press(VTermKey.END) }
            TouchKey("⋯", stringResource(R.string.bridge_more_keys)) { expanded = true; interaction() }
        }
    }
    if (expanded) AlertDialog(onDismissRequest = { expanded = false }, title = { Text(stringResource(R.string.bridge_key_title)) }, text = {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            Text(stringResource(R.string.bridge_modifier_help), style = MaterialTheme.typography.bodySmall)
            for (row in 0..2) Row {
                for (col in 1..4) {
                    val number = row * 4 + col
                    TouchKey("F$number") { press(VTermKey.FUNCTION_1 + number - 1) }
                }
            }
            Row {
                TouchKey("PgUp") { press(VTermKey.PAGEUP) }
                TouchKey("PgDn") { press(VTermKey.PAGEDOWN) }
                TouchKey("Insert") { press(VTermKey.INS) }
                TouchKey("Delete") { press(VTermKey.DEL) }
            }
            Row {
                TouchKey("Ctrl+C", stringResource(R.string.bridge_interrupt)) { bridge.injectString("\u0003"); expanded = false }
                TouchKey("Ctrl+D", stringResource(R.string.bridge_eof)) { bridge.injectString("\u0004"); expanded = false }
                TouchKey("Ctrl+L", stringResource(R.string.bridge_clear)) { bridge.injectString("\u000c"); expanded = false }
            }
            for (chars in listOf(listOf("|", "\\", "/", "~"), listOf("$", "`", "{", "}"), listOf("[", "]", "'", "\""))) Row {
                chars.forEach { character -> TouchKey(character) { bridge.injectString(character); expanded = false } }
            }
            Text(stringResource(R.string.bridge_copy_help), style = MaterialTheme.typography.bodySmall)
        }
    }, confirmButton = { TextButton(onClick = { expanded = false }) { Text(stringResource(R.string.bridge_back_terminal)) } })
}
