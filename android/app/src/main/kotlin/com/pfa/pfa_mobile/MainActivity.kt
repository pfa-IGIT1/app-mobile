package com.pfa.pfa_mobile

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
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
}
