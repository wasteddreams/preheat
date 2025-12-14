/* preheat-ctl.c - CLI control tool for Preheat daemon
 *
 * Copyright (C) 2025 Preheat Contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#define _DEFAULT_SOURCE  /* For usleep() */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <errno.h>
#include <unistd.h>

#define PIDFILE "/var/run/preheat.pid"
#define PACKAGE "preheat"

static void
print_usage(const char *prog)
{
    printf("Usage: %s COMMAND\n\n", prog);
    printf("Control the %s daemon\n\n", PACKAGE);
    printf("Commands:\n");
    printf("  status      Check if daemon is running\n");
    printf("  reload      Reload configuration (send SIGHUP)\n");
    printf("  dump        Dump state to log (send SIGUSR1)\n");
    printf("  save        Save state immediately (send SIGUSR2)\n");
    printf("  stop        Stop daemon gracefully (send SIGTERM)\n");
    printf("  help        Show this help message\n");
    printf("\n");
}

static int
read_pid(void)
{
    FILE *f;
    int pid = -1;
    
    f = fopen(PIDFILE, "r");
    if (!f) {
        if (errno == ENOENT) {
            fprintf(stderr, "Error: PID file %s not found\n", PIDFILE);
            fprintf(stderr, "Is %s running?\n", PACKAGE);
        } else {
            fprintf(stderr, "Error: Cannot read PID file %s: %s\n", 
                    PIDFILE, strerror(errno));
        }
        return -1;
    }
    
    if (fscanf(f, "%d", &pid) != 1) {
        fprintf(stderr, "Error: Invalid PID file format\n");
        fclose(f);
        return -1;
    }
    
    fclose(f);
    return pid;
}

static int
check_running(int pid)
{
    if (kill(pid, 0) == 0) {
        return 1;  /* Running */
    } else {
        if (errno == ESRCH) {
            return 0;  /* Not running */
        } else {
            fprintf(stderr, "Warning: Cannot check process %d: %s\n",
                    pid, strerror(errno));
            return -1;  /* Unknown */
        }
    }
}

static int
send_signal(int pid, int sig, const char *action)
{
    if (kill(pid, sig) < 0) {
        fprintf(stderr, "Error: Failed to send signal to %s (PID %d): %s\n",
                PACKAGE, pid, strerror(errno));
        return 1;
    }
    
    printf("%s: %s\n", PACKAGE, action);
    return 0;
}

static int
cmd_status(void)
{
    int pid = read_pid();
    if (pid < 0)
        return 1;
    
    int status = check_running(pid);
    if (status == 1) {
        printf("%s is running (PID %d)\n", PACKAGE, pid);
        return 0;
    } else if (status == 0) {
        fprintf(stderr, "%s is not running (stale PID file?)\n", PACKAGE);
        return 1;
    } else {
        fprintf(stderr, "%s status unknown\n", PACKAGE);
        return 1;
    }
}

static int
cmd_reload(void)
{
    int pid = read_pid();
    if (pid < 0)
        return 1;
    
    if (!check_running(pid)) {
        fprintf(stderr, "Error: %s is not running\n", PACKAGE);
        return 1;
    }
    
    return send_signal(pid, SIGHUP, "configuration reload requested");
}

static int
cmd_dump(void)
{
    int pid = read_pid();
    if (pid < 0)
        return 1;
    
    if (!check_running(pid)) {
        fprintf(stderr, "Error: %s is not running\n", PACKAGE);
        return 1;
    }
    
    return send_signal(pid, SIGUSR1, "state dump requested");
}

static int
cmd_save(void)
{
    int pid = read_pid();
    if (pid < 0)
        return 1;
    
    if (!check_running(pid)) {
        fprintf(stderr, "Error: %s is not running\n", PACKAGE);
        return 1;
    }
    
    return send_signal(pid, SIGUSR2, "immediate save requested");
}

static int
cmd_stop(void)
{
    int pid = read_pid();
    if (pid < 0)
        return 1;
    
    if (!check_running(pid)) {
        fprintf(stderr, "Error: %s is not running\n", PACKAGE);
        return 1;
    }
    
    int ret = send_signal(pid, SIGTERM, "stop requested");
    if (ret == 0) {
        printf("Waiting for daemon to stop...\n");
        
        /* Wait up to 5 seconds */
        int i;
        for (i = 0; i < 50; i++) {
            usleep(100000);  /* 100ms */
            if (!check_running(pid)) {
                printf("%s stopped\n", PACKAGE);
                return 0;
            }
        }
        
        fprintf(stderr, "Warning: Daemon did not stop after 5 seconds\n");
        return 1;
    }
    
    return ret;
}

int
main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "Error: No command specified\n\n");
        print_usage(argv[0]);
        return 1;
    }
    
    const char *cmd = argv[1];
    
    if (strcmp(cmd, "status") == 0) {
        return cmd_status();
    } else if (strcmp(cmd, "reload") == 0) {
        return cmd_reload();
    } else if (strcmp(cmd, "dump") == 0) {
        return cmd_dump();
    } else if (strcmp(cmd, "save") == 0) {
        return cmd_save();
    } else if (strcmp(cmd, "stop") == 0) {
        return cmd_stop();
    } else if (strcmp(cmd, "help") == 0 || strcmp(cmd, "--help") == 0 || strcmp(cmd, "-h") == 0) {
        print_usage(argv[0]);
        return 0;
    } else {
        fprintf(stderr, "Error: Unknown command '%s'\n\n", cmd);
        print_usage(argv[0]);
        return 1;
    }
}
