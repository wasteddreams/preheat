/* spy.c - Process tracking for Preheat
 *
 * Based on preload 0.6.4 spy.c (VERBATIM implementation)
 * Based on the preload daemon
 * Copyright (C) 2025 Preheat Contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#include "common.h"
#include "spy.h"
#include "../config/config.h"
#include "../state/state.h"
#include "proc.h"

/* Static state for tracking exe changes (VERBATIM from upstream) */
static GSList *state_changed_exes;
static GSList *new_running_exes;
static GHashTable *new_exes;

/**
 * Callback for every running process
 * Check whether we know what it is, and add it to appropriate list
 * (VERBATIM from upstream running_process_callback)
 */
static void
running_process_callback(pid_t pid, const char *path)
{
    kp_exe_t *exe;
    
    g_return_if_fail(path);
    
    exe = g_hash_table_lookup(kp_state->exes, path);
    if (exe) {
        /* Already existing exe */
        
        /* Has it been running already? */
        if (!exe_is_running(exe)) {
            new_running_exes = g_slist_prepend(new_running_exes, exe);
            state_changed_exes = g_slist_prepend(state_changed_exes, exe);
        }
        
        /* Update timestamp */
        exe->running_timestamp = kp_state->time;
        
    } else if (!g_hash_table_lookup(kp_state->bad_exes, path)) {
        /* An exe we have never seen before, just queue it */
        g_hash_table_insert(new_exes, g_strdup(path), GUINT_TO_POINTER(pid));
    }
}

/**
 * For every exe that has been running, check whether it's still running
 * (VERBATIM from upstream already_running_exe_callback)
 */
static void
already_running_exe_callback(kp_exe_t *exe)
{
    if (exe_is_running(exe))
        new_running_exes = g_slist_prepend(new_running_exes, exe);
    else
        state_changed_exes = g_slist_prepend(state_changed_exes, exe);
}

/**
 * There is an exe we've never seen before. Check if it's a piggy one or not.
 * If yes, add it to our farm, add it to the blacklist otherwise.
 * (VERBATIM from upstream new_exe_callback)
 */
static void
new_exe_callback(char *path, pid_t pid)
{
    gboolean want_it;
    size_t size;
    
    size = kp_proc_get_maps(pid, NULL, NULL);
    
    if (!size) /* process died or something */
        return;
    
    want_it = size >= (size_t)kp_conf->model.minsize;
    
    if (want_it) {
        kp_exe_t *exe;
        GSet *exemaps;
        
        size = kp_proc_get_maps(pid, kp_state->maps, &exemaps);
        if (!size) {
            /* Process just died, clean up */
            g_set_foreach(exemaps, (GFunc)kp_exemap_free, NULL);
            g_set_free(exemaps);
            return;
        }
        
        exe = kp_exe_new(path, TRUE, exemaps);
        kp_state_register_exe(exe, TRUE);
        kp_state->running_exes = g_slist_prepend(kp_state->running_exes, exe);
        
    } else {
        g_hash_table_insert(kp_state->bad_exes, g_strdup(path), GINT_TO_POINTER(size));
    }
}

/**
 * Increment time for running markov (state 3 = both exes running)
 * (VERBATIM from upstream running_markov_inc_time)
 */
static void
running_markov_inc_time(kp_markov_t *markov, int time)
{
    if (markov->state == 3)
        markov->time += time;
}

/**
 * Increment time for running exe
 * (VERBATIM from upstream running_exe_inc_time)
 */
static void
running_exe_inc_time(gpointer G_GNUC_UNUSED key, kp_exe_t *exe, int time)
{
    if (exe_is_running(exe))
        exe->time += time;
}

/**
 * Adjust states on exes that change state (running/not-running)
 * (VERBATIM from upstream exe_changed_callback)
 */
static void
exe_changed_callback(kp_exe_t *exe)
{
    exe->change_timestamp = kp_state->time;
    g_set_foreach(exe->markovs, (GFunc)kp_markov_state_changed, NULL);
}

/**
 * Scan processes, see which exes started running, which are not running
 * anymore, and what new exes are around.
 * (VERBATIM from upstream preload_spy_scan)
 */
void
kp_spy_scan(gpointer data)
{
    /* Scan processes */
    state_changed_exes = new_running_exes = NULL;
    new_exes = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
    
    /* Mark each running exe with fresh timestamp */
    kp_proc_foreach((GHFunc)running_process_callback, data);
    kp_state->last_running_timestamp = kp_state->time;
    
    /* Figure out who's not running by checking their timestamp */
    g_slist_foreach(kp_state->running_exes, (GFunc)already_running_exe_callback, data);
    
    g_slist_free(kp_state->running_exes);
    kp_state->running_exes = new_running_exes;
}

/**
 * Update model - run after scan, after some delay (half a cycle)
 * (VERBATIM from upstream preload_spy_update_model)
 */
void
kp_spy_update_model(gpointer data)
{
    int period;
    
    /* Register newly discovered exes */
    g_hash_table_foreach(new_exes, (GHFunc)new_exe_callback, data);
    g_hash_table_destroy(new_exes);
    
    /* And adjust states for those changing */
    g_slist_foreach(state_changed_exes, (GFunc)exe_changed_callback, data);
    g_slist_free(state_changed_exes);
    
    /* Do some accounting */
    period = kp_state->time - kp_state->last_accounting_timestamp;
    g_hash_table_foreach(kp_state->exes, (GHFunc)running_exe_inc_time, GINT_TO_POINTER(period));
    kp_markov_foreach((GFunc)running_markov_inc_time, GINT_TO_POINTER(period));
    kp_state->last_accounting_timestamp = kp_state->time;
}
