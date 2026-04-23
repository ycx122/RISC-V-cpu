/*
 * sw/programs/freertos_demo/main.c
 *
 * FreeRTOS smoke test for the RISC-V-cpu SoC.  Mirrors the layout of
 * sw/programs/os_demo (two worker tasks that take turns and a final
 * PASS banner) but all scheduling is done by FreeRTOS V11.1.0's stock
 * GCC/RISC-V port instead of the hand-rolled cooperative sched.c.
 *
 * Expected UART transcript:
 *
 *   freertos_demo boot
 *   [task0] iter=0 tick=<n>
 *   [task1] iter=0 tick=<n>
 *   [task0] iter=1 tick=<n>
 *   [task1] iter=1 tick=<n>
 *   [task0] iter=2 tick=<n>
 *   [task1] iter=2 tick=<n>
 *   freertos_demo: all tasks finished (ticks=<N>)
 *   OS_DEMO_PASS
 *
 * The OS_DEMO_PASS banner is matched by sim/run_freertos_demo.sh's
 * +UART_PASS_PATTERN; UNHANDLED / TRAP / assert are matched by
 * +UART_FAIL_PATTERN so the test fails loudly.
 *
 * Notes on the port:
 *   - mtvec points directly at freertos_risc_v_trap_handler (set in
 *     init_mtvec() below), NOT at the BSP's bsp_trap_entry.  So we do
 *     NOT call bsp_init() -- it would overwrite mtvec.
 *   - mtimecmp is programmed by the FreeRTOS port at xPortStartScheduler
 *     time, so we do not pre-arm it here.
 *   - The external PLIC interrupt is not enabled: the demo does not need
 *     any peripheral IRQ.  If you wire one up later, install a handler
 *     via freertos_risc_v_application_interrupt_handler() and enable
 *     MIE.MEIE yourself.
 */

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "bsp/bsp.h"
#include "bsp/csr.h"
#include "bsp/plic.h"
#include "bsp/uart.h"

#define TASK_ITERS          3
#define WORKER_STACK_WORDS  (configMINIMAL_STACK_SIZE)
#define WORKER_DELAY_TICKS  (pdMS_TO_TICKS(1))   /* 1 ms @ 10 kHz tick = 10 ticks */

/* ------------------------------------------------------------------ */
/* UART is shared between all tasks.  The hardware UART back-pressure   */
/* is byte-level, so concurrent writes can interleave mid-line.  Wrap  */
/* the puts/printf calls in a FreeRTOS mutex to keep the transcript     */
/* deterministic for the testbench.                                    */
/* ------------------------------------------------------------------ */
#include "semphr.h"
static SemaphoreHandle_t uart_mutex;

static void uart_lock(void)   { if (uart_mutex) xSemaphoreTake(uart_mutex, portMAX_DELAY); }
static void uart_unlock(void) { if (uart_mutex) xSemaphoreGive(uart_mutex); }

/* ------------------------------------------------------------------ */
/* Shared state                                                        */
/* ------------------------------------------------------------------ */
static volatile uint8_t task_done[2];

/* ------------------------------------------------------------------ */
/* Workers                                                             */
/* ------------------------------------------------------------------ */
static void worker_task(void *arg)
{
    const int id = (int)(uintptr_t)arg;

    for (int i = 0; i < TASK_ITERS; i++) {
        uart_lock();
        uart_printf("[task%d] iter=%d tick=%u\n",
                    id, i, (unsigned)xTaskGetTickCount());
        uart_unlock();
        vTaskDelay(WORKER_DELAY_TICKS);
    }

    task_done[id] = 1;

    uart_lock();
    uart_printf("[task%d] done\n", id);
    uart_unlock();

    /* Park forever.  We deliberately avoid vTaskDelete so the scheduler
     * bookkeeping stays small -- the watchdog task is the one that decides
     * when the test is complete and prints the PASS banner.              */
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

/* ------------------------------------------------------------------ */
/* Watchdog: waits for both workers to finish, prints PASS, halts.     */
/* ------------------------------------------------------------------ */
static void watchdog_task(void *arg)
{
    (void)arg;

    while (!(task_done[0] && task_done[1])) {
        vTaskDelay(1);
    }

    uart_lock();
    uart_printf("freertos_demo: all tasks finished (ticks=%u)\n",
                (unsigned)xTaskGetTickCount());
    uart_puts("OS_DEMO_PASS\n");
    uart_unlock();

    /* Park.  The testbench will have already matched the PASS pattern;
     * wfi lets the CPU drop into a low-activity loop so waveform dumps
     * stay small.                                                    */
    for (;;) {
        __asm__ volatile("wfi");
    }
}

/* ------------------------------------------------------------------ */
/* Minimal bring-up.  Replaces bsp_init(): we must NOT let bsp_init    */
/* overwrite mtvec because FreeRTOS needs its own trap handler there.  */
/* ------------------------------------------------------------------ */
extern void freertos_risc_v_trap_handler(void);

static void init_mtvec(void)
{
    /* Direct mode, handler is 4-byte aligned (FreeRTOS aligns to 256). */
    csr_write(mtvec, (uint32_t)(uintptr_t)freertos_risc_v_trap_handler);

    /* Start with a known mstatus: MPP=M so mret stays in M-mode, MIE=0
     * (FreeRTOS enables it inside xPortStartFirstTask).                */
    csr_write(mstatus, MSTATUS_MPP);

    /* Clear any interrupt enables that may have been set by a warm boot
     * UART downloader; port.c sets MIE.MTIE / MIE.MEIE explicitly.     */
    csr_write(mie, 0);

    /* Drain any stale PLIC claim so we do not take a spurious MEI as
     * soon as MIE.MEIE is enabled.  Not strictly needed (the demo does
     * not enable MEIE), but cheap insurance.                          */
    uint32_t irq = plic_claim();
    if (irq) plic_complete(irq);
}

int main(void)
{
    init_mtvec();

    uart_puts("freertos_demo boot\n");

    uart_mutex = xSemaphoreCreateMutex();
    configASSERT(uart_mutex != NULL);

    BaseType_t rc;
    rc = xTaskCreate(worker_task, "task0",
                     WORKER_STACK_WORDS, (void *)(uintptr_t)0,
                     tskIDLE_PRIORITY + 1, NULL);
    configASSERT(rc == pdPASS);
    rc = xTaskCreate(worker_task, "task1",
                     WORKER_STACK_WORDS, (void *)(uintptr_t)1,
                     tskIDLE_PRIORITY + 1, NULL);
    configASSERT(rc == pdPASS);
    rc = xTaskCreate(watchdog_task, "wd",
                     WORKER_STACK_WORDS, NULL,
                     tskIDLE_PRIORITY + 2, NULL);
    configASSERT(rc == pdPASS);

    vTaskStartScheduler();

    /* Should never get here unless the heap was too small for the idle
     * task.  Shout and stop so the testbench fails loudly.            */
    uart_puts("UNHANDLED: vTaskStartScheduler returned\n");
    for (;;) {}
    return 0;
}

/* ------------------------------------------------------------------ */
/* Hooks required by FreeRTOSConfig.h                                   */
/* ------------------------------------------------------------------ */
void vApplicationMallocFailedHook(void)
{
    uart_puts("UNHANDLED: malloc failed\n");
    for (;;) {}
}

void vAssertCalled(const char *file, int line)
{
    uart_puts("UNHANDLED: assert ");
    uart_puts(file);
    uart_printf(":%d\n", line);
    for (;;) {}
}

/* ------------------------------------------------------------------ */
/* FreeRTOS's port.c declares these as weak and jumps to `.` on fault. */
/* Override with a UART banner so the testbench can see why we died.   */
/* The banner tag (UNHANDLED) matches sim/run_freertos_demo.sh's       */
/* +UART_FAIL_PATTERN so a fault turns into a test failure instead of  */
/* a silent simulator timeout.                                         */
/* ------------------------------------------------------------------ */
void freertos_risc_v_application_exception_handler(uint32_t a0_arg)
{
    uint32_t live_mcause = csr_read(mcause);
    uint32_t live_mepc   = csr_read(mepc);
    uart_printf("UNHANDLED-E a0=0x%08x mcause=0x%08x mepc=0x%08x\n",
                a0_arg, live_mcause, live_mepc);
    for (;;) {}
}

void freertos_risc_v_application_interrupt_handler(uint32_t a0_arg)
{
    uint32_t live_mcause = csr_read(mcause);
    uint32_t live_mepc   = csr_read(mepc);
    uint32_t live_mip    = csr_read(mip);
    uart_printf("UNHANDLED-I a0=0x%08x mcause=0x%08x mepc=0x%08x mip=0x%08x\n",
                a0_arg, live_mcause, live_mepc, live_mip);
    for (;;) {}
}
