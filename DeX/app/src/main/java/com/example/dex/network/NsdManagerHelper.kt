package com.example.dex.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo

class NsdManagerHelper(
    private val context: Context,
    private val localInfo: RegisterDto
) {
    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var registrationListener: NsdManager.RegistrationListener? = null

    fun start() {
        registerService()
    }

    fun stop() {
        runCatching { registrationListener?.let { nsdManager.unregisterService(it) } }
        registrationListener = null
    }

    private fun registerService() {
        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "DeX_Android"
            serviceType = "_dex._udp"
            port = localInfo.port
            setAttribute("alias", localInfo.alias)
            setAttribute("fingerprint", localInfo.fingerprint)
            setAttribute("identityHash", localInfo.identityHash)
            setAttribute("deviceModel", localInfo.deviceModel)
            setAttribute("deviceType", localInfo.deviceType)
        }
        
        registrationListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(NsdServiceInfo: NsdServiceInfo) {}
            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
            override fun onServiceUnregistered(arg0: NsdServiceInfo) {}
            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
        }
        
        runCatching { nsdManager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registrationListener) }
    }


}
