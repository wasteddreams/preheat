/* signals.c - Signal handling implementation
 *
 * Based on preload 0.6.4 (VERBATIM signal handling logic)
 * Based on the preload daemon
 * Copyright (C) 2025 Preheat Contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#include "common.h"
#include "signals.h"
#include "../utils/logging.h"
#include "../config/config.h"

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

/**
 * Synchronous signal handler
 * (VERBATIM from upstream preload sig_handler_sync)
 * 
 * Processes signals in the main loop context to avoid race conditions
 */
static gboolean
sig_handler_sync(gpointer data)
{
    int sig = GPOINTER_TO_INT(data);
    
    switch (sig) {
        case SIGHUP:
            /* Reload configuration and reopen log file */
            g_message("SIGHUP received - reloading configuration");
            kp_config_load(conffile, FALSE);
            kp_log_reopen(logfile);
            break;
            
        case SIGUSR1:
            /* Dump current state and config to log */
            g_message("SIGUSR1 received - dumping state");
            kp_state_dump_log();
            kp_config_dump_log();
            break;
            
        case SIGUSR2:
            /* Save state immediately */
            g_message("SIGUSR2 received - saving state");
            kp_state_save(statefile);
            break;
            
        default:
            /* Everything else is an exit request */
            g_message("Exit signal received (%d) - shutting down", sig);
            if (main_loop && g_main_loop_is_running(main_loop)) {
                g_main_loop_quit(main_loop);
            } else {
                /* If main loop not running, exit immediately */
                exit(EXIT_SUCCESS);
            }
            break;
    }
    
    return FALSE;  /* Don't repeat */
}

/**
 * Asynchronous signal handler
 * (VERBATIM from upstream preload sig_handler)
 * 
 * Just schedules synchronous handler in main loop
 */
static RETSIGTYPE
sig_handler(int sig)
{
    /* Schedule sync handler in main loop for thread safety */
    g_timeout_add(0, sig_handler_sync, GINT_TO_POINTER(sig));
}

/**
 * Install signal handlers
 * (VERBATIM from upstream preload set_sig_handlers)
 */
void
kp_signals_init(void)
{
    /* Trap key signals */
    signal(SIGINT,  sig_handler);   /* Ctrl+C */
    signal(SIGQUIT, sig_handler);   /* Ctrl+\ */
    signal(SIGTERM, sig_handler);   /* systemctl stop */
    signal(SIGHUP,  sig_handler);   /* systemctl reload */
    signal(SIGUSR1, sig_handler);   /* dump state */
    signal(SIGUSR2, sig_handler);   /* save state */
    signal(SIGPIPE, SIG_IGN);       /* ignore broken pipes */
    
    g_debug("Signal handlers installed");
}
