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

/** Height of one key row. The bar is exactly two rows tall. */
const val BRIDGE_KEY_ROW_DP = 44

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RowScope.TouchKey(label: String, description: String = label, active: ModifierLevel = ModifierLevel.OFF, accent: Boolean = false, longPress: (() -> Unit)? = null, press: () -> Unit) {
    val fill = when {
        active != ModifierLevel.OFF -> Color(0xFF176E79)
        accent -> Color(0xFF233A5A)
        else -> Color(0xFF1A2B42)
    }
    Box(Modifier.weight(1f).height(BRIDGE_KEY_ROW_DP.dp).padding(horizontal = 1.5.dp, vertical = 2.dp)
        .background(fill, RoundedCornerShape(7.dp))
        .semantics { contentDescription = description + when (active) { ModifierLevel.TRANSIENT -> ", next key"; ModifierLevel.LOCKED -> ", locked"; else -> "" } }
        .combinedClickable(onClick = press, onLongClick = longPress), contentAlignment = Alignment.Center) {
        Text(label + if (active == ModifierLevel.LOCKED) "•" else "", fontSize = 12.5.sp, color = if (accent) Color(0xFF8FF0E8) else Color(0xFFE6F1FF), maxLines = 1, softWrap = false)
    }
}

/** A labelled action in the extra-keys sheet: the key on top, what it does below. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RowScope.SheetKey(key: String, caption: String, press: () -> Unit) {
    Column(Modifier.weight(1f).padding(2.dp).background(Color(0xFF1A2B42), RoundedCornerShape(8.dp))
        .semantics { contentDescription = "$caption, $key" }
        .combinedClickable(onClick = press).padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(key, fontSize = 14.sp, color = Color(0xFF8FF0E8), maxLines = 1, softWrap = false)
        Text(caption, fontSize = 11.sp, color = Color(0xFFB4C3D6), maxLines = 1, softWrap = false)
    }
}

@Composable
private fun SheetHeading(text: String) {
    Text(text, style = MaterialTheme.typography.labelLarge, color = Color(0xFF61E2DA), modifier = Modifier.padding(top = 10.dp, bottom = 2.dp))
}

@Composable
fun BridgeKeyboard(bridge: TerminalBridge, imeVisible: Boolean, showIme: () -> Unit, hideIme: () -> Unit, interaction: () -> Unit, shortcutChanged: () -> Unit, modifier: Modifier = Modifier) {
    val handler = bridge.keyHandler
    val state by handler.modifierState.collectAsState()
    var expanded by remember { mutableStateOf(false) }
    fun press(key: Int) { handler.sendPressedKey(key); interaction(); shortcutChanged() }
    fun send(text: String) { bridge.injectString(text); interaction() }
    fun tap(text: String) { send(text); expanded = false }
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
    Column(modifier.fillMaxWidth().height((BRIDGE_KEY_ROW_DP * 2).dp).background(Color(0xFF0D192B)).padding(horizontal = 3.dp)) {
        Row(Modifier.fillMaxWidth()) {
            TouchKey("Esc") { press(VTermKey.ESCAPE) }
            TouchKey("Tab") { press(VTermKey.TAB) }
            TouchKey("Ctrl", active = state.ctrlState, longPress = { change(TerminalKeyListener.CTRL_ON, state.ctrlState, true) }) { change(TerminalKeyListener.CTRL_ON, state.ctrlState) }
            TouchKey("Alt", active = state.altState, longPress = { change(TerminalKeyListener.ALT_ON, state.altState, true) }) { change(TerminalKeyListener.ALT_ON, state.altState) }
            TouchKey("Shift", active = state.shiftState, longPress = { change(TerminalKeyListener.SHIFT_ON, state.shiftState, true) }) { change(TerminalKeyListener.SHIFT_ON, state.shiftState) }
            TouchKey("^C", stringResource(R.string.bridge_interrupt), accent = true) { send("\u0003") }
            TouchKey("^S", stringResource(R.string.bridge_key_save), accent = true) { send("\u0013") }
            TouchKey("^X", stringResource(R.string.bridge_key_exit), accent = true) { send("\u0018") }
            TouchKey("⌨", stringResource(R.string.bridge_toggle_keyboard)) { if (imeVisible) hideIme() else showIme(); interaction() }
        }
        Row(Modifier.fillMaxWidth()) {
            TouchKey("←", "Left") { press(VTermKey.LEFT) }
            TouchKey("↓", "Down") { press(VTermKey.DOWN) }
            TouchKey("↑", "Up") { press(VTermKey.UP) }
            TouchKey("→", "Right") { press(VTermKey.RIGHT) }
            TouchKey("Home") { press(VTermKey.HOME) }
            TouchKey("End") { press(VTermKey.END) }
            TouchKey("PgUp", "Page up") { press(VTermKey.PAGEUP) }
            TouchKey("PgDn", "Page down") { press(VTermKey.PAGEDOWN) }
            TouchKey("⋯", stringResource(R.string.bridge_more_keys)) { expanded = true; interaction() }
        }
    }
    if (expanded) AlertDialog(onDismissRequest = { expanded = false }, title = { Text(stringResource(R.string.bridge_key_title)) }, text = {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            Text(stringResource(R.string.bridge_modifier_help), style = MaterialTheme.typography.bodySmall)
            SheetHeading("nano")
            Row {
                SheetKey("^O", "Write") { tap("\u000f") }
                SheetKey("^W", "Find") { tap("\u0017") }
                SheetKey("^\\", "Replace") { tap("\u001c") }
                SheetKey("^_", "Go to line") { tap("\u001f") }
            }
            Row {
                SheetKey("^K", "Cut line") { tap("\u000b") }
                SheetKey("^U", "Paste") { tap("\u0015") }
                SheetKey("M-U", "Undo") { tap("\u001bu") }
                SheetKey("M-E", "Redo") { tap("\u001be") }
            }
            Row {
                SheetKey("M-A", "Mark") { tap("\u001ba") }
                SheetKey("M-6", "Copy") { tap("\u001b6") }
                SheetKey("^G", "Help") { tap("\u0007") }
                SheetKey("M-#", "Line nums") { tap("\u001b#") }
            }
            SheetHeading("PowerShell")
            Row {
                SheetKey("^R", "History") { tap("\u0012") }
                SheetKey("^L", "Clear") { tap("\u000c") }
                SheetKey("⇧Tab", "Prev match") { tap("\u001b[Z") }
                SheetKey("^Space", "Menu") { tap("\u0000") }
            }
            Row {
                SheetKey("^D", stringResource(R.string.bridge_eof)) { tap("\u0004") }
                SheetKey("^Z", "Undo") { tap("\u001a") }
                SheetKey("Ins", "Insert") { press(VTermKey.INS); expanded = false }
                SheetKey("Del", "Delete") { press(VTermKey.DEL); expanded = false }
            }
            SheetHeading("Function keys")
            for (row in 0..2) Row {
                for (col in 1..4) {
                    val number = row * 4 + col
                    TouchKey("F$number") { press(VTermKey.FUNCTION_1 + number - 1); expanded = false }
                }
            }
            SheetHeading("Symbols")
            for (chars in listOf(listOf("|", "\\", "/", "~", "-"), listOf("$", "`", "{", "}", "@"), listOf("[", "]", "'", "\"", "#"), listOf("<", ">", "&", ";", "%"))) Row {
                chars.forEach { character -> TouchKey(character) { tap(character) } }
            }
            Text(stringResource(R.string.bridge_copy_help), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 8.dp))
        }
    }, confirmButton = { TextButton(onClick = { expanded = false }) { Text(stringResource(R.string.bridge_back_terminal)) } })
}
