package com.jhh.tank_app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 坦克联机 · 最小经典蓝牙 SPP 传输层(应用内插件)。
 *
 * - host:[startServer] 用 listenUsingInsecureRfcommWithServiceRecord 监听,accept 阻塞等待客机。
 * - guest:[connect] 主动连 host:先 SDP+insecure 连(带重试,刚配对后 SDP 缓存常需暖机),
 *   失败再用反射 createRfcommSocket(1) 兜底(部分国产 ROM 只吃这条路)。
 * - 读:后台线程循环 read,经 EventChannel 上抛字节(主线程派发)。
 * - 写:单线程 executor 串行写,避免阻塞平台主线程。
 *
 * 连接结果以 {ok, error} Map 回传,error 显示在 UI 上便于排查。
 */
object TankBluetooth {
    private const val TAG = "TankBluetooth"
    private const val METHOD_CHANNEL = "tank_app/bluetooth"
    private const val RX_CHANNEL = "tank_app/bluetooth/rx"

    // SPP 标准 UUID(两端必须一致)。
    private val SPP_UUID = java.util.UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private const val SERVER_NAME = "TankBattle"

    private lateinit var appContext: Context
    private val mainHandler = Handler(Looper.getMainLooper())

    private var adapter: BluetoothAdapter? = null
    private var socket: BluetoothSocket? = null
    private var serverSocket: BluetoothServerSocket? = null
    private var acceptThread: Thread? = null
    private val running = AtomicBoolean(false)
    private var rxSink: EventChannel.EventSink? = null

    private val writeExecutor = Executors.newSingleThreadExecutor()

    /** 由 MainActivity 注册通道。 */
    fun register(context: Context, messenger: BinaryMessenger) {
        appContext = context.applicationContext
        adapter = (appContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(::onMethodCall)
        EventChannel(messenger, RX_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { rxSink = sink }
            override fun onCancel(arguments: Any?) { rxSink = null }
        })
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isSupported" -> result.success(adapter != null)
                "isEnabled" -> result.success(adapter?.isEnabled == true)
                "getBondedDevices" -> result.success(bondedDevices())
                "startServer" -> startServer(result)
                "connect" -> connect(call.argument<String>("address"), result)
                "write" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    result.success(if (bytes != null) write(bytes) else false)
                }
                "disconnect" -> { disconnect(); result.success(true) }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "method ${call.method} failed", e)
            result.error("exception", e.message, null)
        }
    }

    private fun bondedDevices(): List<Map<String, String>> {
        val a = adapter ?: return emptyList()
        return a.bondedDevices.map { mapOf("address" to (it.address ?: ""), "name" to (it.name ?: "未知")) }
    }

    /** host:开服务监听。{ok:true} 在客机连入时;否则 {ok:false, error}。 */
    private fun startServer(result: MethodChannel.Result) {
        val a = adapter
        if (a == null || !a.isEnabled) { reply(result, false, "蓝牙未开启"); return }
        if (socket != null) { reply(result, true, null); return } // 已有连接
        disconnectInternal(clearSink = false)
        running.set(true)
        acceptThread = Thread {
            var ok = false
            var err: String? = null
            try {
                val server = a.listenUsingInsecureRfcommWithServiceRecord(SERVER_NAME, SPP_UUID)
                serverSocket = server
                Log.d(TAG, "server listening")
                val s = server.accept() // 阻塞至客机连入
                if (running.get()) {
                    serverSocket = null
                    socket = s
                    startReadLoop(s)
                    ok = true
                } else {
                    try { s.close() } catch (_: Exception) {}
                }
            } catch (e: IOException) {
                err = e.message ?: "监听/accept 失败"
                Log.d(TAG, "server accept failed/cancelled: ${e.message}")
            }
            reply(result, ok, err)
        }.apply { isDaemon = true; start() }
    }

    /**
     * guest:主动连 host。
     * 主路径 createInsecureRfcommSocketToServiceRecord(SDP) + 重试(刚配对 SDP 常需暖机);
     * 仍失败则反射 createRfcommSocket(1) 兜底(部分国产 ROM 只认原始通道)。
     */
    private fun connect(address: String?, result: MethodChannel.Result) {
        val a = adapter
        if (a == null || !a.isEnabled) { reply(result, false, "蓝牙未开启"); return }
        if (address.isNullOrBlank()) { reply(result, false, "无效地址"); return }
        if (socket != null) { reply(result, true, null); return }
        running.set(true)
        Thread {
            var ok = false
            var lastError: String? = null
            try {
                val device = a.getRemoteDevice(address)
                var connected = false
                // 主路径:SDP + insecure,最多 3 次(每次间隔暖机)。
                for (attempt in 1..3) {
                    if (!running.get()) break
                    try {
                        val s = device.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
                        s.connect()
                        socket = s
                        startReadLoop(s)
                        connected = true
                        Log.d(TAG, "connect ok on attempt $attempt")
                        break
                    } catch (e: Exception) {
                        lastError = e.message ?: e.javaClass.simpleName
                        Log.d(TAG, "connect attempt $attempt failed: $lastError")
                        try { Thread.sleep(700) } catch (_: InterruptedException) { break }
                    }
                }
                // 兜底:反射 createRfcommSocket(1)。
                if (!connected && running.get()) {
                    try {
                        val m = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                        val s = m.invoke(device, 1) as BluetoothSocket
                        s.connect()
                        socket = s
                        startReadLoop(s)
                        connected = true
                        Log.d(TAG, "connect ok via reflection fallback")
                    } catch (e: Exception) {
                        lastError = (lastError ?: "") + " | 反射兜底:" + (e.message ?: e.javaClass.simpleName)
                        Log.d(TAG, "reflection fallback failed: ${e.message}")
                    }
                }
                ok = connected
            } catch (e: Exception) {
                lastError = e.message ?: e.javaClass.simpleName
            }
            reply(result, ok, if (ok) null else (lastError ?: "未知错误"))
        }.apply { isDaemon = true; start() }
    }

    private fun startReadLoop(s: BluetoothSocket) {
        val input: InputStream = try {
            s.inputStream
        } catch (e: Exception) {
            Log.e(TAG, "no input stream", e); closeSocket(s); return
        }
        Thread {
            val buf = ByteArray(4096)
            try {
                while (running.get()) {
                    val n = input.read(buf)
                    if (n == -1) break
                    if (n > 0) {
                        val data = buf.copyOfRange(0, n)
                        mainHandler.post { rxSink?.success(data) }
                    }
                }
            } catch (e: IOException) {
                Log.d(TAG, "read ended: ${e.message}")
            } finally {
                if (running.compareAndSet(true, false)) {
                    closeSocket(s)
                    socket = null
                    mainHandler.post {
                        rxSink?.endOfStream() // → Dart onDone = 对端断开
                    }
                }
            }
        }.apply { isDaemon = true; start() }
    }

    private fun write(bytes: ByteArray): Boolean {
        val s = socket ?: return false
        writeExecutor.execute {
            try {
                s.outputStream.apply { write(bytes); flush() }
            } catch (e: IOException) {
                Log.d(TAG, "write failed: ${e.message}")
            }
        }
        return true // 已入队即视为成功(executor 串行保证顺序)
    }

    private fun disconnect() {
        running.set(false)
        disconnectInternal(clearSink = true)
    }

    private fun disconnectInternal(clearSink: Boolean) {
        try { acceptThread?.interrupt() } catch (_: Exception) {}
        acceptThread = null
        try { serverSocket?.close() } catch (_: Exception) {}
        serverSocket = null
        closeSocket(socket)
        socket = null
        if (clearSink) mainHandler.post { rxSink?.endOfStream() }
    }

    private fun closeSocket(s: BluetoothSocket?) {
        try { s?.close() } catch (_: Exception) {}
    }

    /** 平台结果必须主线程回复;返回 {ok, error}。 */
    private fun reply(result: MethodChannel.Result, ok: Boolean, error: String?) {
        val map = hashMapOf("ok" to ok, "error" to error)
        mainHandler.post { result.success(map) }
    }
}
