package com.example.dex.network

import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import java.math.BigInteger
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.SecureRandom
import java.util.Date

object SecurityProvider {
    fun generateKeyStore(password: CharArray): KeyStore {
        val keyPairGenerator = KeyPairGenerator.getInstance("RSA")
        keyPairGenerator.initialize(2048, SecureRandom())
        val keyPair: KeyPair = keyPairGenerator.generateKeyPair()

        val issuerName = X500Name("CN=LocalSend")
        val subjectName = issuerName
        val serial = BigInteger(160, SecureRandom())
        val notBefore = Date(System.currentTimeMillis() - 86400000L * 365) // 1 year ago
        val notAfter = Date(System.currentTimeMillis() + 86400000L * 3650) // 10 years valid

        val certBuilder = JcaX509v3CertificateBuilder(
            issuerName, serial, notBefore, notAfter, subjectName, keyPair.public
        )

        val signer = JcaContentSignerBuilder("SHA256WithRSAEncryption").build(keyPair.private)
        val certHolder = certBuilder.build(signer)
        val certificate = JcaX509CertificateConverter().getCertificate(certHolder)

        val keyStore = KeyStore.getInstance(KeyStore.getDefaultType())
        keyStore.load(null, null)
        keyStore.setKeyEntry(
            "localsend_key",
            keyPair.private,
            password,
            arrayOf(certificate)
        )
        return keyStore
    }
}
