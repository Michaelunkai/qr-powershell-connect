// SPDX-License-Identifier: Apache-2.0
package org.connectbot.bridge

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Private key bytes remain encrypted at rest; Android owns the wrapping key. */
object BridgeKeyVault {
    private const val ALIAS = "powershell-connect-wrapping-v1"
    private val marker = "PSKEY1".toByteArray(Charsets.US_ASCII)

    @Synchronized
    private fun key(create: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        check(create) { "The device key is unavailable. Pair this app again." }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
        }.generateKey()
    }

    fun wrap(plain: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(true))
        return marker + cipher.iv + cipher.doFinal(plain)
    }

    fun unwrapIfNeeded(bytes: ByteArray): ByteArray {
        if (bytes.size < marker.size || !bytes.copyOfRange(0, marker.size).contentEquals(marker)) return bytes
        require(bytes.size >= marker.size + 12 + 16) { "Invalid protected key" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, bytes.copyOfRange(6, 18)))
        return cipher.doFinal(bytes.copyOfRange(18, bytes.size))
    }
}
