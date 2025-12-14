/* logging.c - Preheat logging implementation
 *
 * Based on preload 0.6.4 log.c
 * Based on the preload daemon
 * Copyright (C) 2025 Preheat Contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#include "common.h"
#include "logging.h"

#include <time.h>

/* Default log level (0=none, 4=standard, 9=debug) */
#define DEFAULT_LOGLEVEL 4

/* Global log level */
int kp_log_level = DEFAULT_LOGLEVEL;

/**
 * Internal log handler
 * Formats messages with timestamp and passes to GLib logging
 * (VERBATIM from upstream preload_log)
 */
static void
kp_log_handler(const char *log_domain,
               GLogLevelFlags log_level,
               const char *message,
               gpointer G_GNUC_UNUSED user_data)
{
    time_t curtime;
    char *timestr;

    /* Ignore unimportant messages (upstream logic) */
    if (log_level <= G_LOG_LEVEL_ERROR << kp_log_level) {
        curtime = time(NULL);
        timestr = ctime(&curtime);
        timestr[strlen(timestr) - 1] = '\0';  /* Remove trailing newline */
        
        fprintf(stderr, "[%s] %s%s%s\n",
                timestr,
                log_domain ? log_domain : "",
                log_domain ? ": " : "",
                message);
    }

    /* Handle fatal errors (upstream logic) */
    if (log_level & G_LOG_FLAG_FATAL) {
        kp_log_handler(log_domain, 0, "Exiting", NULL);
        fflush(stdout);
        fflush(stderr);
        exit(EXIT_FAILURE);
    }
}

/**
 * Initialize logging system
 * (VERBATIM from upstream preload_log_init)
 */
void
kp_log_init(const char *logfile)
{
    if (logfile && *logfile) {
        int logfd;
        int nullfd;

        /* Set up stdout, stderr to log and stdin to /dev/null */

        if (0 > (nullfd = open("/dev/null", O_RDONLY)))
            g_error("cannot open %s: %s", "/dev/null", strerror(errno));

        if (0 > (logfd = open(logfile, O_WRONLY | O_CREAT | O_APPEND, 0600)))
            g_error("cannot open %s: %s", logfile, strerror(errno));

        if ((dup2(nullfd, STDIN_FILENO) != STDIN_FILENO) ||
            (dup2(logfd, STDOUT_FILENO) != STDOUT_FILENO) ||
            (dup2(logfd, STDERR_FILENO) != STDERR_FILENO))
            g_error("dup2: %s", strerror(errno));

        close(nullfd);
        close(logfd);
    }

    /* Install our custom log handler */
    g_log_set_default_handler(kp_log_handler, NULL);
}

/**
 * Reopen log file after rotation
 * (VERBATIM from upstream preload_log_reopen)
 */
void
kp_log_reopen(const char *logfile)
{
    int logfd;

    if (!(logfile && *logfile))
        return;

    g_message("reopening log file %s", logfile);

    fflush(stdout);
    fflush(stderr);

    if (0 > (logfd = open(logfile, O_WRONLY | O_CREAT | O_APPEND, 0600))) {
        g_warning("cannot reopen %s: %s", logfile, strerror(errno));
        return;
    }

    if ((dup2(logfd, STDOUT_FILENO) != STDOUT_FILENO) ||
        (dup2(logfd, STDERR_FILENO) != STDERR_FILENO))
        g_warning("dup2: %s", strerror(errno));

    close(logfd);

    g_message("reopening log file %s done", logfile);
}
