package com.sdknwdtvpv.lianleme

import android.content.Context
import android.health.connect.HealthConnectException
import android.health.connect.HealthConnectManager
import android.health.connect.ReadRecordsRequestUsingFilters
import android.health.connect.ReadRecordsResponse
import android.health.connect.TimeInstantRangeFilter
import android.health.connect.datatypes.BodyFatRecord
import android.health.connect.datatypes.HeightRecord
import android.health.connect.datatypes.Record
import android.health.connect.datatypes.WeightRecord
import android.os.OutcomeReceiver
import androidx.annotation.RequiresApi
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * 从**系统健康库**读体成分 —— Android 14+ 那条路（平台自带的 Health Connect）。
 *
 * ## 为什么单独一个文件、而且整份都标着 `@RequiresApi(34)`
 *
 * `android.health.connect.*` 这些类**只在 API 34（Android 14）及以上存在**。
 * 把它们和"版本判断"写在一起的话，老设备一进来就可能在**类加载/校验**阶段炸
 * （`NoClassDefFoundError`），而不是在你那条 `if (SDK_INT >= 34)` 里安静地跳过。
 * 所以：**这一份只在真的走上 34+ 那条分支时才会被加载**（见 `HealthBridge.isAvailable`），
 * 老设备上它连类都不会被解析。这是 Android 上处理"新 API + 老系统"的标准做法，
 * 也是这个仓库里"平台没实现就安静降级"那条约定的一种写法。
 *
 * ## 为什么用平台 API 而不是 `androidx.health.connect:connect-client`
 *
 * 那个 Jetpack 库的 `AndroidManifest` 写着 `android:minSdkVersion="26"`（2026-10-09 亲眼看
 * `connect-client-1.1.0.aar` 里读出来的），用了它就得把我们的 `minSdk` 从 24 抬到 26 ——
 * **等于放弃 Android 7 的用户**，那是产品承诺，不是顺手能改的数字。
 * 而 Android 14+ 的 Health Connect 是**系统内置**的（Mainline 模块），平台 API 就在
 * `android.health.connect` 包里，一行依赖都不用加 —— 与这个仓库"依赖越少越好"的一贯做法一致。
 * 代价说清楚：**Android 13 及以下读不到**（那一档要靠上面那个库 + 抬 minSdk 才能覆盖，
 * 见 `docs/plan-health-sync.md` §七），所以那一档上入口不会出现。
 *
 * ## 只读不写
 *
 * 这里**没有任何写入路径**，也不申请任何 `WRITE_*` 权限 —— 政策里承诺的是"只读、不写回"，
 * 那一句由 `tool/privacy-audit.mjs` 的 ⑩之六 核着（iOS 那半边核的是 `toShare: []`）。
 */
@RequiresApi(34)
object HealthConnectApi34 {

  private val executor = Executors.newSingleThreadExecutor()

  /** 系统里有没有 Health Connect 这个模块。没有（比如某些精简 ROM）就当作"读不到"。 */
  fun manager(context: Context): HealthConnectManager? =
    context.getSystemService(HealthConnectManager::class.java)

  /**
   * 读最近 [days] 天的体重 / 体脂率 / 身高，每条测量各自一条样本。
   *
   * 分组（"同一天取最新"）**不在这里做** —— 那是 `health_sync.dart` 的活，
   * 这一层只负责把系统里的数按原样交出去（与 iOS 那份同一个分工）。
   * 三种类型各发一个异步查询，全部回来后回调一次；**任何一路出错都只丢那一路**，
   * 不让一条查询失败把整次同步变成"什么都没有"。
   */
  fun read(context: Context, days: Int, onDone: (List<Map<String, Any?>>) -> Unit) {
    val manager = manager(context)
    if (manager == null) {
      onDone(emptyList())
      return
    }
    val end = Instant.now()
    val start = end.minus(days.coerceAtLeast(1).toLong(), ChronoUnit.DAYS)
    val out = ArrayList<Map<String, Any?>>()
    val pending = AtomicInteger(3)

    fun finishOne() {
      if (pending.decrementAndGet() == 0) onDone(out)
    }

    fun <T : Record> query(type: Class<T>, toSample: (T) -> Map<String, Any?>) {
      val request = ReadRecordsRequestUsingFilters.Builder(type)
        // ⚠️ 平台这边**没有** `TimeRangeFilter.between(...)` 那个工厂
        //（Jetpack 库里有，平台 API 里只有两个具体类）。绝对时间的那个是
        // `TimeInstantRangeFilter`，用它的 Builder 起止两个 Instant 都设上。
        .setTimeRangeFilter(
          TimeInstantRangeFilter.Builder().setStartTime(start).setEndTime(end).build(),
        )
        // 新的在前 —— 与 iOS 那份同一个顺序（谁先到不影响结果，但报错时好看）
        .setAscending(false)
        .setPageSize(1000)
        .build()
      manager.readRecords(
        request,
        executor,
        object : OutcomeReceiver<ReadRecordsResponse<T>, HealthConnectException> {
          override fun onResult(response: ReadRecordsResponse<T>) {
            for (record in response.records) {
              val sample = toSample(record)
              if (sample.isNotEmpty()) out.add(sample)
            }
            finishOne()
          }

          override fun onError(error: HealthConnectException) {
            // 没授权 / 这个类型没有任何数据 / 系统那边出错 —— 都只是"这一路没有"
            finishOne()
          }
        },
      )
    }

    query(WeightRecord::class.java) { record ->
      mapOf("atMs" to record.time.toEpochMilli(), "weightKg" to record.weight.inGrams / 1000.0)
    }
    query(BodyFatRecord::class.java) { record ->
      mapOf("atMs" to record.time.toEpochMilli(), "bodyFatPct" to percentToNumber(record.percentage.value))
    }
    query(HeightRecord::class.java) { record ->
      mapOf("atMs" to record.time.toEpochMilli(), "heightCm" to record.height.inMeters * 100.0)
    }
  }

  /**
   * 体脂率那个单位换算 —— **写成了一个带护栏的纯函数**，因为它有一个真陷阱。
   *
   * Health Connect 的 `Percentage` 语义是"分数"（0.18 = 18%），与 iOS 的 `HKUnit.percent()`
   * 一样；但这两处**都没有在真机上验过**（见 §七"还没验的那一件事"）。
   * 所以这里不赌：**小于 1.5 当作分数乘 100，否则当作已经是百分数**。
   * 人体体脂率不可能低到 1.5% 以下，所以这个分界不会误伤真实数据 ——
   * 而对"它其实是 0–100"的那种实现，这道护栏正好救回来。
   */
  internal fun percentToNumber(value: Double): Double =
    if (value <= 1.5) value * 100.0 else value
}
