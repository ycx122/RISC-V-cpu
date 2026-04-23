/*
 * sw/programs/freertos_demo/FreeRTOSConfig.h
 *
 * FreeRTOS configuration tailored to the RISC-V-cpu SoC (rtl/soc/cpu_soc.v):
 *   - 50 MHz cpu_clk (clk_wiz_0 output divider = 1, matches the testbench
 *     `always #10 clk = ~clk` toggle period).
 *   - SiFive-layout CLINT at 0x4200_0000, so mtime at 0x4200_BFF8 and
 *     mtimecmp at 0x4200_4000 (see sw/bsp/include/bsp/clint.h).
 *   - No F/D/V extensions; RV32IM only; no MPU/PMP.
 *
 * Tick rate is deliberately high (10 kHz) to keep the simulation cycle
 * budget reasonable: one tick == 5 000 cpu_clk cycles, which means a
 * handful of context switches finish in well under 1 M cycles.  A real
 * board can drop this back to 1 kHz without touching anything else.
 */

#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

/* ------------------------------------------------------------------ */
/* Hardware mapping                                                    */
/* ------------------------------------------------------------------ */
#define configCPU_CLOCK_HZ                      (50000000UL)
#define configMTIME_BASE_ADDRESS                (0x4200BFF8UL)
#define configMTIMECMP_BASE_ADDRESS             (0x42004000UL)

/* ------------------------------------------------------------------ */
/* Scheduler                                                           */
/* ------------------------------------------------------------------ */
#define configTICK_RATE_HZ                      ((TickType_t)10000)
#define configUSE_PREEMPTION                    1
#define configUSE_TIME_SLICING                  1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 1
#define configUSE_TICKLESS_IDLE                 0
#define configMAX_PRIORITIES                    5
#define configMINIMAL_STACK_SIZE                ((unsigned short)256)
#define configMAX_TASK_NAME_LEN                 12
#define configUSE_16_BIT_TICKS                  0
#define configIDLE_SHOULD_YIELD                 1
#define configUSE_TASK_NOTIFICATIONS            1
#define configTASK_NOTIFICATION_ARRAY_ENTRIES   1

/* ------------------------------------------------------------------ */
/* Memory allocation                                                   */
/* ------------------------------------------------------------------ */
#define configSUPPORT_DYNAMIC_ALLOCATION        1
#define configSUPPORT_STATIC_ALLOCATION         0
#define configTOTAL_HEAP_SIZE                   ((size_t)(32 * 1024))
#define configAPPLICATION_ALLOCATED_HEAP        0

/* ------------------------------------------------------------------ */
/* ISR stack used by freertos_risc_v_trap_handler.  Statically         */
/* allocated so we do NOT need __freertos_irq_stack_top from the       */
/* linker script.  2 KB is plenty for this port's context-save frame   */
/* (31 GPRs + mstatus + critical nesting = 33 words + any nesting).    */
/* ------------------------------------------------------------------ */
#define configISR_STACK_SIZE_WORDS              (512)

/* ------------------------------------------------------------------ */
/* Hook functions                                                      */
/* ------------------------------------------------------------------ */
#define configUSE_IDLE_HOOK                     0
#define configUSE_TICK_HOOK                     0
#define configUSE_MALLOC_FAILED_HOOK            1
#define configCHECK_FOR_STACK_OVERFLOW          0

/* ------------------------------------------------------------------ */
/* Features trimmed to keep ROM footprint under 64 KB                  */
/* ------------------------------------------------------------------ */
#define configUSE_MUTEXES                       1
#define configUSE_RECURSIVE_MUTEXES             0
#define configUSE_COUNTING_SEMAPHORES           1
#define configUSE_QUEUE_SETS                    0
#define configQUEUE_REGISTRY_SIZE               0
#define configUSE_TRACE_FACILITY                0
#define configUSE_STATS_FORMATTING_FUNCTIONS    0
#define configGENERATE_RUN_TIME_STATS           0
#define configUSE_CO_ROUTINES                   0
#define configUSE_TIMERS                        0
#define configUSE_NEWLIB_REENTRANT              0

/* Include / exclude specific API functions. */
#define INCLUDE_vTaskPrioritySet                0
#define INCLUDE_uxTaskPriorityGet               0
#define INCLUDE_vTaskDelete                     1
#define INCLUDE_vTaskSuspend                    0
#define INCLUDE_vTaskDelayUntil                 1
#define INCLUDE_vTaskDelay                      1
#define INCLUDE_xTaskGetSchedulerState          1
#define INCLUDE_xTaskGetCurrentTaskHandle       1
#define INCLUDE_uxTaskGetStackHighWaterMark     0
#define INCLUDE_eTaskGetState                   0
#define INCLUDE_xTimerPendFunctionCall          0
#define INCLUDE_xTaskAbortDelay                 0
#define INCLUDE_xTaskGetHandle                  0

/* ------------------------------------------------------------------ */
/* configASSERT: trap into our banner on failure so the testbench can   */
/* observe a deterministic failure signature (+UART_FAIL_PATTERN).     */
/* ------------------------------------------------------------------ */
#ifndef __ASSEMBLER__
extern void vAssertCalled(const char *file, int line);
#define configASSERT(x)                                                   \
    do {                                                                   \
        if ((x) == 0) vAssertCalled(__FILE__, __LINE__);                  \
    } while (0)
#endif

#endif /* FREERTOS_CONFIG_H */
