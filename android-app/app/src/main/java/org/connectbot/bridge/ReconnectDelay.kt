// SPDX-License-Identifier: Apache-2.0
package org.connectbot.bridge

/** Avoid tight reconnect loops while a host is booting or temporarily offline. */
object ReconnectDelay {
    fun milliseconds(attempt: Int): Long = (1000L shl attempt.coerceIn(0, 5)).coerceAtMost(30000L)
}
