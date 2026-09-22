// SPDX-License-Identifier: Apache-2.0
package org.connectbot.bridge

import android.app.Application
import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], manifest = Config.NONE)
class TailscaleStartupTest {
    @Test fun requestsApprovedVpnThroughExplicitReceiverWhenOffline() {
        val app: Application = RuntimeEnvironment.getApplication()
        TailscaleStartup.connectIfNeeded(app)
        val intent = shadowOf(app).broadcastIntents.last()
        assertEquals("com.tailscale.ipn.CONNECT_VPN", intent.action)
        assertEquals("com.tailscale.ipn", intent.component?.packageName)
        assertEquals("com.tailscale.ipn.IPNReceiver", intent.component?.className)
        assertTrue(intent.flags and Intent.FLAG_INCLUDE_STOPPED_PACKAGES != 0)
    }
}
