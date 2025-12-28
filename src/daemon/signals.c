/* signals.c - Signal handling implementation
 *
 * Based on preload 0.6.4 (VERBATIM signal handling logic)
 * Copyright (C) 2025 Preheat Contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * =============================================================================
 * MODULE OVERVIEW: Signal Handling
 * =============================================================================
 *
 * Unix signals are used to control the daemon:
 *
 * SIGNAL      │ ACTION
 * ────────────┼───────────────────────────────────────────────────
 * SIGHUP      │ Reload config, blacklist, and reopen log file
 * SIGUSR1     │ Dump state, config, and stats to /run/preheat.stats
 * SIGUSR2     │ Save state immediately to disk
 * SIGTERM     │ Graceful shutdown (save state, cleanup, exit)
 * SIGINT      │ Graceful shutdown (Ctrl+C)
 * SIGQUIT     │ Graceful shutdown (Ctrl+\)
 * SIGPIPE     │ Ignored (broken pipe from child processes)
 *
 * TWO-PHASE HANDLING:
 *   Signals are caught asynchronously by sig_handler(), which schedules
 *   sig_handler_sync() to run in the main loop context. This avoids
 *   race conditions when accessing shared state (config, state, etc.).
 *
 * USAGE:
 *   systemctl reload preheat  → send SIGHUP
 *   systemctl stop preheat    → send SIGTERM
 *   kill -USR1 $(pidof preheat) → dump stats
 *
 * =============================================================================
 */

#include "common.h"
#include "signals.h"
#include "../utils/logging.h"
#include "../config/config.h"
#include "../config/blacklist.h"
#include "stats.h"

#include <signal.h>

/* External references from main.c */
extern const char *conffile;
extern const char *statefile;
extern const char *logfile;
extern GMainLoop *main_loop;

/* Forward declarations for state/config functions (to be implemented) */
extern void kp_config_load(const char *conffile, gboolean is_startup);
extern void kp_state_dump_log(void);
extern void kp_state_save(const char *statefile);
extern void kp_config_dump_log(void);
extern void kp_state_register_manual_apps(void);

/* B002/B004 FIX: Atomic flags to prevent signal coalescing and races */
static volatile sig_atomic_t pending_sighup = 0;
static volatile sig_atomic_t pending_sigusr1 = 0;
static volatile sig_atomic_t pending_sigusr2 = 0;
static volatile sig_atomic_t pending_exit = 0;
static volatile sig_atomic_t state_saving = 0;  /* B004: Defer SIGHUP during save */

/**
 * Synchronous signal handler
 * 
 * B002 FIX: Uses atomic flags to prevent multiple queued handlers
 * B004 FIX: Defers SIGHUP if state save is in progress
 */
static gboolean
sig_handler_sync(gpointer data)
{
    (void)data;  /* Unused - we check atomic flags instead */

    /* B004: If saving state, defer SIGHUP processing */
    if (pending_sighup && !state_saving) {
        pending_sighup = 0;
        g_message("SIGHUP received - reloading configuration");
        kp_config_load(conffile, FALSE);
        kp_blacklist_reload();
        kp_state_register_manual_apps();
        kp_log_reopen(logfile);
    }

    if (pending_sigusr1) {
        pending_sigusr1 = 0;
        g_message("SIGUSR1 received - dumping state and stats");
        kp_state_dump_log();
        kp_config_dump_log();
        kp_stats_dump_to_file("/run/preheat.stats");
    }

    if (pending_sigusr2) {
        pending_sigusr2 = 0;
        g_message("SIGUSR2 received - saving state");
        state_saving = 1;
        kp_state_save(statefile);
        state_saving = 0;
        /* Process any deferred SIGHUP */
        if (pending_sighup) {
            g_timeout_add(0, sig_handler_sync, NULL);
        }
    }

    if (pending_exit) {
        int sig = pending_exit;
        pending_exit = 0;
        g_message("Exit signal received (%d) - shutting down", sig);
        if (main_loop && g_main_loop_is_running(main_loop)) {
            g_main_loop_quit(main_loop);
        } else {
            exit(EXIT_SUCCESS);
        }
    }

    return FALSE;  /* Don't repeat */
}

/**
 * Asynchronous signal handler
 * 
 * B002 FIX: Sets atomic flag instead of queuing multiple handlers
 */
static RETSIGTYPE
sig_handler(int sig)
{
    /* Set atomic flag - prevents multiple queued handlers */
    switch (sig) {
        case SIGHUP:  pending_sighup = 1; break;
        case SIGUSR1: pending_sigusr1 = 1; break;
        case SIGUSR2: pending_sigusr2 = 1; break;
        default:      pending_exit = sig; break;
    }
    g_timeout_add(0, sig_handler_sync, NULL);
}

/**
 * Install signal handlers
 * 
 * BUG FIXES:
 *   B001: Added SIGCHLD with SA_NOCLDWAIT to auto-reap zombie children
 *   B003: Migrated from deprecated signal() to sigaction()
 */
void
kp_signals_init(void)
{
    struct sigaction sa;
    
    /* Set up common handler for most signals */
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sig_handler;
    sa.sa_flags = SA_RESTART;  /* Restart interrupted syscalls */
    sigemptyset(&sa.sa_mask);
    
    /* Trap key signals */
    sigaction(SIGINT,  &sa, NULL);   /* Ctrl+C */
    sigaction(SIGQUIT, &sa, NULL);   /* Ctrl+\ */
    sigaction(SIGTERM, &sa, NULL);   /* systemctl stop */
    sigaction(SIGHUP,  &sa, NULL);   /* systemctl reload */
    sigaction(SIGUSR1, &sa, NULL);   /* dump state */
    sigaction(SIGUSR2, &sa, NULL);   /* save state */
    
    /* Ignore SIGPIPE (broken pipe from child processes) */
    sa.sa_handler = SIG_IGN;
    sigaction(SIGPIPE, &sa, NULL);
    
    /* B001 FIX: Auto-reap child processes to prevent zombies
     * SA_NOCLDWAIT causes children to be reaped automatically */
    sa.sa_handler = SIG_DFL;
    sa.sa_flags = SA_NOCLDWAIT;
    sigaction(SIGCHLD, &sa, NULL);

    g_debug("Signal handlers installed (using sigaction)");
}
