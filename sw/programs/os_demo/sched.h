/*
 * sw/programs/os_demo/sched.h
 *
 * Cooperative round-robin scheduler for the os_demo BSP test.  Tasks
 * only ever give up the CPU when they call task_yield() -- the timer
 * interrupt just increments a tick counter, it does NOT pre-empt.
 *
 * This is intentionally small: a real RTOS port (FreeRTOS / RT-Thread)
 * reuses the same BSP (sw/bsp/) but brings its own scheduler; this
 * file exists to prove the BSP round-trip (trap entry + CLINT arming +
 * UART printf + context save/restore) end-to-end.
 */

#ifndef OS_DEMO_SCHED_H
#define OS_DEMO_SCHED_H

#include <stdint.h>

#define SCHED_MAX_TASKS  4
#define SCHED_STACK_SIZE 2048

/* Callee-saved registers + ra + sp.  Coop switches never cross a trap
 * boundary so caller-saved state (t*, a*) lives in registers only
 * across the function call, never in the frame.                       */
struct sched_ctx {
    uint32_t ra;
    uint32_t sp;
    uint32_t s0;
    uint32_t s1;
    uint32_t s2;
    uint32_t s3;
    uint32_t s4;
    uint32_t s5;
    uint32_t s6;
    uint32_t s7;
    uint32_t s8;
    uint32_t s9;
    uint32_t s10;
    uint32_t s11;
};

/* Install the caller as task 0 ("the main thread").  Must be called
 * before task_create / task_yield so that cur_task is valid.  The
 * current s-regs / sp / ra are not snapshotted here; the first
 * task_yield() naturally saves them into ctx[0] as part of switching
 * to the new task.                                                    */
void sched_init(void);

/* Register a new task.  Returns the task id on success, or -1 on
 * overflow.  Task stacks are statically allocated.                    */
int  task_create(void (*entry)(void));

/* Yield the CPU to the next ready task (round-robin).  With a single
 * task registered this is a no-op.                                     */
void task_yield(void);

/* Exposed for the asm switcher.  Not intended to be called directly
 * from application code.                                               */
void sched_switch(struct sched_ctx *prev, struct sched_ctx *next);

#endif /* OS_DEMO_SCHED_H */
