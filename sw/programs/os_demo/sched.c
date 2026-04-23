/*
 * sw/programs/os_demo/sched.c
 *
 * Minimal cooperative scheduler.  See sched.h for the contract.
 */

#include <stdint.h>
#include "sched.h"

static struct sched_ctx    tasks[SCHED_MAX_TASKS];
static uint8_t             stacks[SCHED_MAX_TASKS][SCHED_STACK_SIZE]
                               __attribute__((aligned(16)));
static int                 ntasks;
static int                 cur_task = -1;

void sched_init(void)
{
    ntasks   = 1;
    cur_task = 0;
    /* ctx[0] is left zero-initialised; the first task_yield() call
     * snapshots the live callee-saved regs into it before switching.  */
}

int task_create(void (*entry)(void))
{
    if (ntasks >= SCHED_MAX_TASKS) {
        return -1;
    }

    int id = ntasks++;
    struct sched_ctx *c = &tasks[id];

    /* When the scheduler first switches to this task, sched_switch
     * will `lw ra, <ra>(a1); lw sp, <sp>(a1); ret`, so the task wakes
     * up at `entry` with its own private stack.  Everything else is
     * irrelevant: task entries take no arguments, and the callee-
     * saved regs don't need a defined value on first entry.  Avoid
     * memset here because we link -nostdlib.                          */
    uint32_t *p = (uint32_t *)c;
    for (unsigned i = 0; i < sizeof(*c) / sizeof(uint32_t); i++) {
        p[i] = 0;
    }
    c->ra = (uint32_t)(uintptr_t)entry;
    c->sp = (uint32_t)(uintptr_t)&stacks[id][SCHED_STACK_SIZE];
    return id;
}

void task_yield(void)
{
    if (ntasks <= 1) return;
    int prev = cur_task;
    int next = (cur_task + 1) % ntasks;
    cur_task = next;
    sched_switch(&tasks[prev], &tasks[next]);
}
