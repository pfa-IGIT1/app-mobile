package com.pfa.pfa_mobile

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import java.net.Inet4Address
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tranasi/network")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindToWifi" -> result.success(bindToWifi())
                    "wifiGateway" -> result.success(wifiGateway())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Attache le processus au réseau WiFi, même sans accès Internet (WiFi du
     * dongle). Sans WiFi connecté : détache (évite de rester lié à un réseau
     * disparu) et renvoie false.
     */
    private fun bindToWifi(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        @Suppress("DEPRECATION")
        val wifi = cm.allNetworks.firstOrNull { network ->
            cm.getNetworkCapabilities(network)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
        if (wifi == null) {
            cm.bindProcessToNetwork(null)
            return false
        }
        return cm.bindProcessToNetwork(wifi)
    }

    /**
     * Adresse IPv4 de la passerelle du WiFi courant (route par défaut fournie
     * par le DHCP du dongle). Repli : adresse du serveur DHCP. `null` si le
     * téléphone n'est pas sur un WiFi.
     */
    private fun wifiGateway(): String? {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        @Suppress("DEPRECATION")
        val wifi = cm.allNetworks.firstOrNull { network ->
            cm.getNetworkCapabilities(network)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        } ?: return null
        val viaRoute = cm.getLinkProperties(wifi)?.routes
            ?.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }
            ?.gateway?.hostAddress
        if (!viaRoute.isNullOrEmpty()) return viaRoute
        @Suppress("DEPRECATION")
        val server = (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
            .dhcpInfo?.serverAddress ?: 0
        if (server == 0) return null
        return "${server and 0xff}.${server shr 8 and 0xff}.${server shr 16 and 0xff}.${server shr 24 and 0xff}"
    }
}
