package com.example.n_queens_solver

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import com.chaquo.python.Python
import com.chaquo.python.PyObject
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
    class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.n_queens_solver/vision"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "runVisionEngine" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("ARG_ERROR", "Missing image path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val py = Python.getInstance()
                            val module: PyObject = py.getModule("vision_engine")
                            val pyResult: PyObject = module.callAttr("process_image", path)
                            // Convert Python dict → JSON string → Map for Flutter
                            val jsonString = pyResult.toString()
                            val map = JSONObject(jsonString).toMap()
                            result.success(map)
                        } catch (e: Exception) {
                            result.error("PY_ERR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}


/* Helpers to turn a JSONObject into a Kotlin Map */
fun JSONObject.toMap(): Map<String, Any?> = keys().asSequence().associateWith { key ->
    when (val value = this[key]) {
        is JSONObject -> value.toMap()
        is org.json.JSONArray -> value.toList()
        else -> value
    }
}
fun org.json.JSONArray.toList(): List<Any?> = (0 until length()).map { i ->
    when (val value = get(i)) {
        is JSONObject -> value.toMap()
        is org.json.JSONArray -> value.toList()
        else -> value
    }
}
