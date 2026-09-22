// SPDX-License-Identifier: Apache-2.0
package org.connectbot.bridge
import org.junit.Assert.*
import org.junit.Test

class ReconnectDelayTest {
    @Test fun retriesBackOffAndStayBounded() {
        assertEquals(listOf(1000L,2000L,4000L,8000L,16000L,30000L,30000L), (0..6).map(ReconnectDelay::milliseconds))
        assertEquals(30000L, ReconnectDelay.milliseconds(Int.MAX_VALUE))
        assertEquals(1000L, ReconnectDelay.milliseconds(-1))
    }
}
