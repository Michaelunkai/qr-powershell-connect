// SPDX-License-Identifier: Apache-2.0
package org.connectbot.bridge

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities

/** Requests an existing, approved Tailscale VPN; never bypasses Android consent. */
object TailscaleStartup {
    fun connectIfNeeded(context: Context) {
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val meshPresent = connectivity.allNetworks.any { network ->
            connectivity.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true &&
                connectivity.getLinkProperties(network)?.linkAddresses.orEmpty().any {
                    val bytes = it.address.address
                    bytes.size == 4 && (bytes[0].toInt() and 255) == 100 &&
                        (bytes[1].toInt() and 255) in 64..127
                }
        }
        if (meshPresent) return
        context.sendBroadcast(
            Intent("com.tailscale.ipn.CONNECT_VPN")
                .setComponent(ComponentName("com.tailscale.ipn", "com.tailscale.ipn.IPNReceiver"))
                .addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES),
        )
    }
}
