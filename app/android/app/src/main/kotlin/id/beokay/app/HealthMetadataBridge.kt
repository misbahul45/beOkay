package id.beokay.app

import android.content.Context
import android.content.Intent
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.BloodGlucoseRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import kotlin.reflect.KClass
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class HealthMetadataBridge(private val context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "lookup" -> {
                    val types = (call.argument<List<String>>("types") ?: emptyList()).toSet()
                    val start = call.argument<Number>("start")?.toLong() ?: 0L
                    val end = call.argument<Number>("end")?.toLong() ?: 0L
                    scope.launch {
                        val out = try {
                            withContext(Dispatchers.IO) { lookup(types, start, end) }
                        } catch (e: Exception) {
                            emptyMap()
                        }
                        result.success(out)
                    }
                }
                "openSettings" -> result.success(openSettings())
                else -> result.notImplemented()
            }
        }
    }

    private fun openSettings(): Boolean = try {
        val intent = Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    private suspend fun lookup(types: Set<String>, start: Long, end: Long): Map<String, Map<String, String?>> {
        if (HealthConnectClient.getSdkStatus(context) != HealthConnectClient.SDK_AVAILABLE) return emptyMap()
        val client = HealthConnectClient.getOrCreate(context)
        val from = Instant.ofEpochMilli(start)
        val to = Instant.ofEpochMilli(end)
        val out = HashMap<String, Map<String, String?>>()
        if ("heartRate" in types) collect(client, HeartRateRecord::class, from, to, out)
        if ("restingHeartRate" in types) collect(client, RestingHeartRateRecord::class, from, to, out)
        if ("sleep" in types) collect(client, SleepSessionRecord::class, from, to, out)
        if ("weight" in types) collect(client, WeightRecord::class, from, to, out)
        if ("glucose" in types) collect(client, BloodGlucoseRecord::class, from, to, out)
        if ("workouts" in types) collect(client, ExerciseSessionRecord::class, from, to, out)
        return out
    }

    private suspend fun <T : Record> collect(
        client: HealthConnectClient,
        type: KClass<T>,
        from: Instant,
        to: Instant,
        out: MutableMap<String, Map<String, String?>>,
    ) {
        var token: String? = null
        var pages = 0
        do {
            val response = client.readRecords(
                ReadRecordsRequest(
                    recordType = type,
                    timeRangeFilter = TimeRangeFilter.between(from, to),
                    pageSize = 1000,
                    pageToken = token,
                ),
            )
            for (record in response.records) {
                val device = record.metadata.device ?: continue
                out[record.metadata.id] = mapOf(
                    "type" to typeName(device.type),
                    "manufacturer" to device.manufacturer,
                    "model" to device.model,
                )
            }
            token = response.pageToken
            pages++
        } while (token != null && pages < MAX_PAGES)
    }

    private fun typeName(type: Int): String = when (type) {
        Device.TYPE_WATCH -> "watch"
        Device.TYPE_PHONE -> "phone"
        Device.TYPE_RING -> "ring"
        Device.TYPE_SCALE -> "scale"
        Device.TYPE_CHEST_STRAP -> "chest_strap"
        Device.TYPE_FITNESS_BAND -> "fitness_band"
        Device.TYPE_HEAD_MOUNTED -> "head_mounted"
        else -> "unknown"
    }

    companion object {
        const val CHANNEL = "beokay/health_metadata"
        const val MAX_PAGES = 20
    }
}
