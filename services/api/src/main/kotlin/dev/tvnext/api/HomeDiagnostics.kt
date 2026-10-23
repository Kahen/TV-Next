package dev.tvnext.api

import io.micrometer.core.instrument.MeterRegistry
import java.lang.management.ManagementFactory
import org.springframework.web.bind.annotation.*

data class HomeDiagnostics(
    val uptimeSeconds: Long, val memoryUsedBytes: Long, val memoryMaxBytes: Long,
    val httpRequests: Long, val httpClientErrors: Long, val httpServerErrors: Long,
    val devices: Int, val onlineDevices: Int, val libraryRevision: Long
)

/** Aggregate process counters plus only the authenticated user's device/library totals. */
@RestController
@RequestMapping("/api/v1/home")
class HomeDiagnosticsController(private val accounts: HomeAccounts, private val remote: RemoteControl,
    private val library: LibrarySync, private val meters: MeterRegistry) {
    @GetMapping("/diagnostics")
    fun diagnostics(@RequestHeader("Authorization",required=false) auth: String?): HomeDiagnostics {
        val principal=accounts.principal(auth)
        val runtime=Runtime.getRuntime()
        val timers=meters.find("http.server.requests").timers()
        val devices=remote.devices(principal)
        fun errors(prefix: String)=timers.filter { it.id.getTag("status")?.startsWith(prefix)==true }.sumOf { it.count() }
        return HomeDiagnostics(ManagementFactory.getRuntimeMXBean().uptime/1000,
            runtime.totalMemory()-runtime.freeMemory(),runtime.maxMemory(),timers.sumOf { it.count() },errors("4"),errors("5"),
            devices.size,devices.count { it.online },library.read(principal).revision)
    }
}
