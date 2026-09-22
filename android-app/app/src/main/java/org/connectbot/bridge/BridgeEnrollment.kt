// SPDX-License-Identifier: Apache-2.0
package org.connectbot.bridge

import android.util.Base64
import org.json.JSONObject
import java.net.URI
import java.net.URL
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

data class BridgeTicket(val host: String, val port: Int, val pin: String, val token: String, val expires: Long)

object BridgeEnrollment {
    fun requireMeshHost(host: String) {
        require(Regex("100\\.(?:[0-9]{1,3}\\.)[0-9]{1,3}\\.[0-9]{1,3}").matches(host)) { "Expected a Tailscale IPv4 address" }
        val parts = host.split('.').map { it.toInt() }
        require(parts[1] in 64..127 && parts.all { it in 0..255 }) { "Expected a Tailscale IPv4 address" }
        require(parts.joinToString(".") == host) { "Invalid address format" }
    }

    fun parse(link: String, now: Long = System.currentTimeMillis() / 1000): BridgeTicket {
        require(link.length in 40..4096) { "Scan a complete, fresh pairing QR" }
        val uri = URI(link.trim())
        val legacy = uri.scheme == "https" && uri.host == "qrbridge.invalid" && uri.port == -1
        require(uri.userInfo == null && uri.query == null && uri.path == "/enroll") { "Invalid pairing link" }
        require(legacy || (uri.scheme == "http" && uri.port == 8080)) { "Invalid pairing link" }
        val fragment = uri.fragment ?: error("Pairing link is incomplete")
        require(Regex("[A-Za-z0-9_-]{40,4000}").matches(fragment)) { "Invalid pairing details" }
        val data = JSONObject(String(Base64.decode(fragment, Base64.URL_SAFE or Base64.NO_WRAP), Charsets.UTF_8))
        require(data.getInt("v") == 1) { "Unsupported pairing version" }
        val host = data.getString("host")
        requireMeshHost(host)
        require(legacy || uri.host == host) { "Pairing hosts do not match" }
        val port = data.getInt("port")
        val pin = data.getString("pin")
        val token = data.getString("token")
        val expires = data.getLong("expires")
        require(port in 1024..65535 && Regex("[a-f0-9]{64}").matches(pin) && Regex("[A-Za-z0-9_-]{43}").matches(token)) { "Invalid pairing details" }
        require(expires > now && expires <= now + 1800) { "QR expired. Generate a fresh QR on Windows." }
        return BridgeTicket(host, port, pin, token, expires)
    }

    fun enroll(ticket: BridgeTicket, publicKey: String): JSONObject {
        val trust = object : X509TrustManager {
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) = throw java.security.cert.CertificateException("Client certificates unsupported")
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                val cert = chain.firstOrNull() ?: throw java.security.cert.CertificateException("Missing host certificate")
                val digest = MessageDigest.getInstance("SHA-256").digest(cert.encoded).joinToString("") { "%02x".format(it.toInt() and 255) }
                if (!MessageDigest.isEqual(digest.toByteArray(), ticket.pin.toByteArray())) throw java.security.cert.CertificateException("Certificate pin mismatch")
            }
        }
        val context = SSLContext.getInstance("TLS").apply { init(null, arrayOf<TrustManager>(trust), SecureRandom()) }
        val connection = URL("https://${ticket.host}:${ticket.port}/enroll").openConnection() as HttpsURLConnection
        connection.sslSocketFactory = context.socketFactory
        connection.connectTimeout = 10000
        connection.readTimeout = 10000
        connection.instanceFollowRedirects = false
        connection.requestMethod = "POST"
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/json")
        try {
            val body = JSONObject().put("token", ticket.token).put("key", publicKey).toString().toByteArray()
            connection.setFixedLengthStreamingMode(body.size)
            connection.outputStream.use { it.write(body) }
            require(connection.responseCode == 200) { "Pairing rejected. Generate a fresh QR and try again." }
            val response = connection.inputStream.use { it.readBytesBounded(8192) }
            return JSONObject(String(response, Charsets.UTF_8)).also { require(it.getString("host") == ticket.host) { "SSH destination changed" } }
        } finally { connection.disconnect() }
    }

    private fun java.io.InputStream.readBytesBounded(limit: Int): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(1024)
        while (true) {
            val count = read(buffer)
            if (count < 0) break
            require(output.size() + count <= limit) { "Pairing response too large" }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }
}
