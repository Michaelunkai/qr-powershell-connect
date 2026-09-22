// SPDX-License-Identifier: Apache-2.0
package org.connectbot.bridge

import org.connectbot.service.*
import org.connectbot.terminal.VTermKey
import org.junit.Assert.*
import org.junit.Test

class BridgeModifiersTest {
    @Test fun shiftTabSendsShiftAndClearsOneShot() {
        val events = mutableListOf<Pair<Int, Int>>()
        val handler = TerminalKeyListener(KeyDispatcher { modifiers, key -> events.add(modifiers to key) })
        handler.metaPress(TerminalKeyListener.SHIFT_ON, true)
        handler.sendTab()
        assertEquals(listOf(1 to VTermKey.TAB), events)
        assertEquals(ModifierLevel.OFF, handler.modifierState.value.shiftState)
    }
    @Test fun lockedControlPersistsAcrossArrowKeys() {
        val events = mutableListOf<Pair<Int, Int>>()
        val handler = TerminalKeyListener(KeyDispatcher { modifiers, key -> events.add(modifiers to key) })
        repeat(2) { handler.metaPress(TerminalKeyListener.CTRL_ON, true) }
        handler.sendPressedKey(VTermKey.LEFT)
        handler.sendPressedKey(VTermKey.RIGHT)
        assertEquals(listOf(4 to VTermKey.LEFT, 4 to VTermKey.RIGHT), events)
        assertEquals(ModifierLevel.LOCKED, handler.modifierState.value.ctrlState)
    }
}
