/*
 * sw/programs/os_demo/main.c
 *
 * Smoke test for the sw/bsp/ BSP.  Exercises the full stack:
 *   - BSP trap entry + dispatch
 *   - CLINT timer interrupt arming and re-arming
 *   - UART printf
 *   - cooperative context switch between two worker tasks + main
 *
 * Expected UART transcript (ordering between task 0 and task 1 is
 * deterministic because there is no pre-emption in coop mode):
 *
 *   os_demo boot
 *   [task0] iter=0 tick=<n>
 *   [task1] iter=0 tick=<n>
 *   [task0] iter=1 tick=<n>
 *   [task1] iter=1 tick=<n>
 *   [task0] iter=2 tick=<n>
 *   [task1] iter=2 tick=<n>
 *   os_demo: all tasks finished (ticks=<N>)
 *   OS_DEMO_PASS
 *
 * The `OS_DEMO_PASS` banner is what sim/tb/cpu_test.v's
 * +UART_PASS_PATTERN is looking for -- see sim/run_os_demo.sh.
 */

#include <stdint.h>

#include "bsp/bsp.h"
#include "bsp/clint.h"
#include "bsp/csr.h"
#include "bsp/trap.h"
#include "bsp/uart.h"

#include "sched.h"

#define TASK_ITERS          3

/* 100 us per tick at the 50 MHz clk_wiz output.  Short on purpose: the
 * OS demo should finish in well under 1 ms of wall-clock simulation
 * time so it stays inside the default testbench cycle budget.         */
#define TICK_INTERVAL_TICKS  CLINT_US_TO_TICKS(100)

static volatile uint32_t timer_count;
static volatile uint8_t  task_done[2];

static void timer_tick(const struct bsp_trap_frame *f)
{
    (void)f;
    timer_count++;
    /* Re-arm the one-shot comparator for the next tick.  If the tick
     * were ever to slip past the new target we'd re-trap immediately,
     * which is the intended behaviour -- it just means the CPU was
     * saturated and we want the scheduler to keep accumulating ticks. */
    clint_schedule_relative(TICK_INTERVAL_TICKS);
}

static void task0(void)
{
    for (int i = 0; i < TASK_ITERS; i++) {
        uart_printf("[task0] iter=%d tick=%u\n", i, timer_count);
        task_yield();
    }
    task_done[0] = 1;
    /* Park: keep yielding so the sibling task + main can run to their
     * completion checks.  Real RTOSes would sleep here instead.       */
    for (;;) task_yield();
}

static void task1(void)
{
    for (int i = 0; i < TASK_ITERS; i++) {
        uart_printf("[task1] iter=%d tick=%u\n", i, timer_count);
        task_yield();
    }
    task_done[1] = 1;
    for (;;) task_yield();
}

int main(void)
{
    bsp_init();
    uart_puts("os_demo boot\n");

    bsp_set_timer_handler(timer_tick);
    clint_schedule_relative(TICK_INTERVAL_TICKS);
    bsp_enable_timer_interrupt();
    bsp_irq_enable();

    sched_init();
    if (task_create(task0) < 0 || task_create(task1) < 0) {
        uart_puts("os_demo: task_create failed\n");
        for (;;) {}
    }

    while (!(task_done[0] && task_done[1])) {
        task_yield();
    }

    bsp_irq_disable();

    uart_printf("os_demo: all tasks finished (ticks=%u)\n", timer_count);
    uart_puts("OS_DEMO_PASS\n");

    for (;;) {
        __asm__ volatile("wfi");
    }
    return 0;
}
