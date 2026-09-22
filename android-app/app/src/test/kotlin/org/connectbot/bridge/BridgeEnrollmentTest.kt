// SPDX-License-Identifier: Apache-2.0
package org.connectbot.bridge

import android.util.Base64
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], manifest = Config.NONE)
class BridgeEnrollmentTest {
    private fun link(host: String = "100.90.80.70", outer: String = host, expires: Long = 1200): String {
        val json = JSONObject().put("v", 1).put("host", host).put("port", 8443)
            .put("pin", "b".repeat(64)).put("token", "a".repeat(43)).put("expires", expires)
        return "http://$outer:8080/enroll#" + Base64.encodeToString(json.toString().toByteArray(), Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }
    @Test fun acceptsValidPinnedMeshTicket() {
        val ticket = BridgeEnrollment.parse(link(), 1000)
        assertEquals("100.90.80.70", ticket.host)
        assertEquals(8443, ticket.port)
    }
    @Test fun rejectsPublicAddress() { assertThrows(IllegalArgumentException::class.java) { BridgeEnrollment.parse(link("8.8.8.8"), 1000) } }
    @Test fun rejectsHostSubstitution() { assertThrows(IllegalArgumentException::class.java) { BridgeEnrollment.parse(link(outer = "100.76.198.54"), 1000) } }
    @Test fun rejectsExpiredTicket() { assertThrows(IllegalArgumentException::class.java) { BridgeEnrollment.parse(link(expires = 999), 1000) } }
    @Test fun rejectsIndefiniteTicket() { assertThrows(IllegalArgumentException::class.java) { BridgeEnrollment.parse(link(expires = 999999), 1000) } }
    @Test fun rejectsCommandInjectionHost() { assertThrows(IllegalArgumentException::class.java) { BridgeEnrollment.requireMeshHost("100.90.80.70\nProxyCommand evil") } }
    @Test fun rejectsLeadingZeros() { assertThrows(IllegalArgumentException::class.java) { BridgeEnrollment.requireMeshHost("100.076.198.53") } }
    @Test fun rejectsMalformedToken() { assertThrows(IllegalArgumentException::class.java) { BridgeEnrollment.parse("http://100.90.80.70:8080/enroll#bad", 1000) } }
}
