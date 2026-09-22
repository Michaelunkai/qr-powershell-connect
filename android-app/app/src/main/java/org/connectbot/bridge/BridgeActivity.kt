// SPDX-License-Identifier: Apache-2.0
package org.connectbot.bridge

import android.content.Intent
import android.os.Bundle
import android.util.Base64
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.lifecycleScope
import androidx.preference.PreferenceManager
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import com.trilead.ssh2.crypto.keys.Ed25519Provider
import com.trilead.ssh2.crypto.keys.Ed25519PublicKey
import com.trilead.ssh2.signature.Ed25519Verify
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.connectbot.data.HostRepository
import org.connectbot.data.PubkeyRepository
import org.connectbot.data.ProfileRepository
import org.connectbot.data.entity.Host
import org.connectbot.data.entity.Pubkey
import org.connectbot.ui.MainActivity
import org.connectbot.di.CoroutineDispatchers
import androidx.compose.ui.res.stringResource
import org.connectbot.R
import org.connectbot.ui.theme.ConnectBotTheme
import org.connectbot.util.PreferenceConstants
import org.connectbot.util.ThemeMode
import org.json.JSONObject
import java.io.File
import java.security.KeyPairGenerator
import javax.inject.Inject

@AndroidEntryPoint
class BridgeActivity : AppCompatActivity() {
    @Inject lateinit var hosts: HostRepository
    @Inject lateinit var keys: PubkeyRepository
    @Inject lateinit var profiles: ProfileRepository
    @Inject lateinit var dispatchers: CoroutineDispatchers
    private var message by mutableStateOf("")
    private var busy by mutableStateOf(true)
    private var link by mutableStateOf("")
    private var ready = false
    private val prefs by lazy { getSharedPreferences("powershell-bridge", MODE_PRIVATE) }
    private val scanner = registerForActivityResult(ScanContract()) { result ->
        result.contents?.let { pair(it) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        TailscaleStartup.connectIfNeeded(this)
        message = getString(R.string.bridge_preparing)
        if (!prefs.getBoolean("defaults", false)) {
            PreferenceManager.getDefaultSharedPreferences(this).edit()
                .putBoolean(PreferenceConstants.KEY_ALWAYS_VISIBLE, true)
                .putBoolean(PreferenceConstants.IME_TOGGLE_KEY, true)
                .putBoolean(PreferenceConstants.CONNECTION_PERSIST, true)
                .putBoolean(PreferenceConstants.TITLEBARHIDE, false)
                .putString(PreferenceConstants.THEME_MODE, "DARK")
                .putString(PreferenceConstants.ROTATION, PreferenceConstants.ROTATION_AUTO).apply()
            prefs.edit().putBoolean("defaults", true).apply()
        }
        setContent {
            ConnectBotTheme(themeMode = ThemeMode.DARK, dynamicColor = false) {
                Surface(color = Color(0xFF091321), modifier = Modifier.fillMaxSize()) {
                    Column(Modifier.safeDrawingPadding().imePadding().verticalScroll(rememberScrollState()).padding(28.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                        Spacer(Modifier.height(28.dp))
                        Text(">_", fontSize = 54.sp, color = Color(0xFF61E2DA), fontWeight = FontWeight.Bold)
                        Text(stringResource(R.string.bridge_title), fontSize = 36.sp, lineHeight = 42.sp, fontWeight = FontWeight.Bold)
                        Text(stringResource(R.string.bridge_brand), color = Color(0xFF61E2DA), style = MaterialTheme.typography.labelLarge)
                        Text(stringResource(R.string.bridge_subtitle), color = Color(0xFFB4C3D6))
                        Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF152339))) {
                            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                                Text(message)
                            }
                        }
                        Button(onClick = { scanner.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setPrompt(getString(R.string.bridge_scan_prompt)).setBeepEnabled(false).setOrientationLocked(false)) }, enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text(stringResource(R.string.bridge_scan)) }
                        OutlinedTextField(value = link, onValueChange = { link = it }, label = { Text(stringResource(R.string.bridge_paste_link)) }, modifier = Modifier.fillMaxWidth(), minLines = 2, maxLines = 4, enabled = !busy)
                        OutlinedButton(onClick = { pair(link) }, enabled = !busy && link.isNotBlank(), modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text(stringResource(R.string.bridge_connect)) }
                        TextButton(onClick = { checkProvisioning() }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.bridge_check)) }
                        Text(stringResource(R.string.bridge_footer), style = MaterialTheme.typography.bodySmall, color = Color(0xFFB4C3D6))
                    }
                }
            }
        }
        lifecycleScope.launch {
            try {
                val key = ensureKey()
                withContext(dispatchers.io) {
                    File(getExternalFilesDir(null), "device-public-key.txt").writeText(publicText(key))
                }
                ready = true
                val saved = prefs.getLong("host", 0)
                val host = if (saved > 0) hosts.findHostById(saved) else null
                if (host != null) open(host) else { busy = false; checkProvisioning() }
            } catch (e: Exception) { fail(e) }
        }
    }

    override fun onResume() {
        super.onResume()
        if (ready && !busy) checkProvisioning()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (ready && !busy) checkProvisioning()
    }

    private suspend fun ensureKey(): Pubkey = withContext(dispatchers.io) {
        keys.getByNickname("PowerShell phone") ?: run {
            Ed25519Provider.insertIfNeeded()
            val pair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
            keys.save(Pubkey(nickname = "PowerShell phone", type = "Ed25519",
                privateKey = BridgeKeyVault.wrap(pair.private.encoded), publicKey = pair.public.encoded,
                encrypted = false, startup = false, confirmation = false,
                createdDate = System.currentTimeMillis(), allowBackup = false))
        }
    }

    private fun publicText(key: Pubkey): String {
        val pub = Ed25519PublicKey(java.security.spec.X509EncodedKeySpec(key.publicKey))
        return "ssh-ed25519 " + Base64.encodeToString(Ed25519Verify.get().encodePublicKey(pub), Base64.NO_WRAP)
    }

    private fun checkProvisioning() {
        if (busy) return
        val file = File(getExternalFilesDir(null), "connection.json")
        busy = true
        lifecycleScope.launch {
            try {
                require(prefs.getLong("host", 0) == 0L) { "This app is already paired." }
                val data = withContext(dispatchers.io) {
                    if (!file.exists()) null else { require(file.length() <= 8192); JSONObject(file.readText()) }
                }
                if (data == null) { message = getString(R.string.bridge_ready); busy = false; return@launch }
                val key = ensureKey()
                require(data.getString("devicePublicKey") == publicText(key)) { "This connection belongs to a different phone key." }
                val host = saveConnection(data, key)
                withContext(dispatchers.io) { file.delete() }
                open(host)
            } catch (e: Exception) { fail(e) }
        }
    }

    private fun pair(uri: String) {
        if (busy) return
        busy = true
        message = getString(R.string.bridge_verifying)
        lifecycleScope.launch {
            try {
                val ticket = BridgeEnrollment.parse(uri)
                val key = ensureKey()
                val response = withContext(dispatchers.io) { BridgeEnrollment.enroll(ticket, publicText(key)) }
                link = ""
                open(saveConnection(response, key))
            } catch (e: Exception) { fail(e) }
        }
    }

    private suspend fun saveConnection(data: JSONObject, key: Pubkey): Host {
        val hostname = data.getString("host")
        BridgeEnrollment.requireMeshHost(hostname)
        val port = data.getInt("port")
        val user = data.getString("user")
        val hostkey = data.getString("hostkey")
        require(port in 1024..65535 && Regex("[a-zA-Z0-9_.-]{1,64}").matches(user)) { "Invalid Windows account or port" }
        require(Regex("ssh-ed25519 [A-Za-z0-9+/]+={0,2}").matches(hostkey)) { "Invalid SSH host key" }
        val raw = Base64.decode(hostkey.substringAfter(' '), Base64.NO_WRAP)
        Ed25519Verify.get().decodePublicKey(raw)
        val profile = profiles.getDefault()
        profiles.update(profile.copy(fontSize = 13, emulation = "xterm-256color"))
        val existing = hosts.getHosts().find { it.nickname == "Windows" }
        val host = hosts.saveHost(Host(id = existing?.id ?: 0, nickname = "Windows", hostname = hostname, port = port,
            username = user, pubkeyId = key.id, hostKeyAlgo = "ssh-ed25519", stayConnected = true,
            scrollbackLines = 5000, profileId = profile.id, ipVersion = "IPV4_ONLY"))
        hosts.deleteKnownHostsForHost(host.id)
        hosts.saveKnownHost(host, hostname, port, "ssh-ed25519", raw)
        withContext(dispatchers.io) { check(prefs.edit().putLong("host", host.id).commit()) { "Could not save connection" } }
        return host
    }

    private fun open(host: Host) {
        startActivity(Intent(this, MainActivity::class.java).setAction(Intent.ACTION_VIEW).setData(host.getUri()))
        if (!prefs.getBoolean("shortcutRequested", false) && ShortcutManagerCompat.isRequestPinShortcutSupported(this)) {
            val shortcut = ShortcutInfoCompat.Builder(this, "windows-terminal")
                .setShortLabel("PowerShell")
                .setLongLabel("Windows PowerShell")
                .setIcon(IconCompat.createWithResource(this, R.drawable.bridge_icon_foreground))
                .setIntent(Intent(this, BridgeActivity::class.java).setAction(Intent.ACTION_MAIN))
                .build()
            if (ShortcutManagerCompat.requestPinShortcut(this, shortcut, null)) prefs.edit().putBoolean("shortcutRequested", true).apply()
        }
        finish()
    }

    private fun fail(error: Exception) {
        busy = false
        // Never log links, TLS capabilities or key material.
        message = when (error) {
            is java.net.ConnectException, is java.net.SocketTimeoutException -> getString(R.string.bridge_unreachable)
            is javax.net.ssl.SSLException -> getString(R.string.bridge_tls_error)
            is IllegalArgumentException -> error.message ?: getString(R.string.bridge_invalid)
            else -> getString(R.string.bridge_failed)
        }
    }
}
