package com.example.smartcare

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "smartcare/cellular"
    private var callback: ConnectivityManager.NetworkCallback? = null
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bind" -> bindCellular(result)
                    "unbind" -> {
                        unbind()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun bindCellular(result: MethodChannel.Result) {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        unbind()
        var replied = false
        fun reply(ok: Boolean, message: String?) {
            if (replied) return
            replied = true
            if (ok) result.success(true)
            else result.error("unavailable", message, null)
        }
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                cm.bindProcessToNetwork(network)
                main.post { reply(true, null) }
            }
            override fun onUnavailable() {
                main.post {
                    reply(false, "بيانات الجوال غير متاحة. فعّل شبكة الجوال ثم أعد المحاولة")
                }
            }
        }
        callback = cb
        try {
            cm.requestNetwork(request, cb)
            main.postDelayed({
                reply(false, "انتهت مهلة ربط شبكة الجوال. تأكد أن بيانات الجوال تعمل")
            }, 10000)
        } catch (e: Exception) {
            reply(false, e.message ?: "تعذر طلب شبكة الجوال")
        }
    }

    private fun unbind() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.bindProcessToNetwork(null)
        callback?.let {
            try {
                cm.unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
        }
        callback = null
    }

    override fun onDestroy() {
        unbind()
        super.onDestroy()
    }
}
