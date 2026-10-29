// SPDX-License-Identifier: Apache-2.0
package org.connectbot.transport

import com.trilead.ssh2.IpVersion
import com.trilead.ssh2.ProxyData
import java.io.IOException
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Direct TCP connection that keeps a handle on its socket.
 *
 * The SSH library holds its own locks while it waits for a reply, so a
 * connection whose peer silently vanished cannot be interrupted through the
 * library. Closing the socket from outside always works: the receive thread
 * fails at once and the normal disconnect and reconnect path runs.
 */
class TrackingProxyData(private val ipVersion: IpVersion) : ProxyData {
    @Volatile
    var socket: Socket? = null
        private set

    override fun openConnection(hostname: String, port: Int, connectTimeout: Int): Socket {
        val all = InetAddress.getAllByName(hostname).toList()
        val candidates = when (ipVersion) {
            IpVersion.IPV4_ONLY -> all.filterIsInstance<Inet4Address>()
            IpVersion.IPV6_ONLY -> all.filterIsInstance<Inet6Address>()
            else -> all.sortedBy { if (it is Inet4Address) 0 else 1 }
        }
        if (candidates.isEmpty()) throw IOException("No usable address for $hostname")
        var last: IOException? = null
        for (address in candidates) {
            val candidate = Socket()
            try {
                candidate.tcpNoDelay = true
                candidate.keepAlive = true
                candidate.connect(InetSocketAddress(address, port), connectTimeout)
                socket = candidate
                return candidate
            } catch (e: IOException) {
                last = e
                try { candidate.close() } catch (_: IOException) {}
            }
        }
        throw last ?: IOException("Could not connect to $hostname")
    }

    /** Tear the connection down immediately, whatever the SSH layer is waiting on. */
    fun abort() {
        try { socket?.close() } catch (_: IOException) {}
    }
}
