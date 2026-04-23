# sw/programs/os_demo/Makefile
#
# Build the os_demo BSP smoke test.  See ../../bsp/README.md for what
# the shared bsp.mk fragment provides.

APP_NAME  := os_demo

APP_CSRCS := main.c sched.c
APP_ASRCS := switch.S

# -O1 keeps the ROM footprint tight enough (~3 KB as of this commit)
# while still leaving the sched_switch save/restore inlined sensibly.
APP_CFLAGS := -Os -g -I.

include ../../bsp/bsp.mk
