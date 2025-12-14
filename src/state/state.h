/* state.h - State management for Preheat
 *
 * Based on preload 0.6.4 state.h (VERBATIM structures)
 * Based on the preload daemon
 * Copyright (C) 2025 Preheat Contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#ifndef STATE_H
#define STATE_H

#include "common.h"
#include "../monitor/proc.h"

/* GSet compatibility macros (from upstream common.h) */
#define GSet                GPtrArray
#define g_set_new()         g_ptr_array_new()
#define g_set_add(s,v)      g_ptr_array_add(s, v)
#define g_set_remove(s,v)   g_ptr_array_remove_fast(s, v)
#define g_set_free(s)       g_ptr_array_free(s, TRUE)
#define g_set_size(s)       ((s)->len)
#define g_set_foreach       g_ptr_array_foreach

/* File path max length (from upstream common.h) */
#define FILELEN 512
#define FILELENSTR "511"

/**
 * kp_map_t: Memory map information
 * (VERBATIM from upstream preload_map_t)
 */
typedef struct _kp_map_t
{
    char *path;         /* Absolute path of the mapped file */
    size_t offset;      /* Offset in bytes */
    size_t length;      /* Length in bytes */
    int update_time;    /* Last time it was probed */
    
    /* Runtime fields: */
    int refcount;       /* Number of exes linking to this */
    double lnprob;      /* Log-probability of NOT being needed in next period */
    int seq;            /* Unique map sequence number */
    int block;          /* On-disk location of the start of the map */
    int priv;           /* For private local use of functions */
} kp_map_t;

/**
 * kp_exemap_t: Mapped section in an executable
 * (VERBATIM from upstream preload_exemap_t)
 */
typedef struct _kp_exemap_t
{
    kp_map_t *map;
    double prob;        /* Probability that this map is used when exe is running */
} kp_exemap_t;

/**
 * kp_exe_t: Executable information
 * (VERBATIM from upstream preload_exe_t)
 */
typedef struct _kp_exe_t
{
    char *path;                 /* Absolute path of the executable */
    int time;                   /* Total time that this has been running, ever */
    int update_time;            /* Last time it was probed */
    GSet *markovs;              /* Set of markov chains with other exes */
    GSet *exemaps;              /* Set of exemap structures */
    
    /* Runtime fields: */
    size_t size;                /* Sum of the size of the maps, in bytes */
    int running_timestamp;      /* Last time it was running */
    int change_timestamp;       /* Time started/stopped running */
    double lnprob;              /* Log-probability of NOT being needed in next period */
    int seq;                    /* Unique exe sequence number */
} kp_exe_t;

#define exe_is_running(exe) ((exe)->running_timestamp >= kp_state->last_running_timestamp)

/**
 * kp_markov_t: 4-state continuous-time Markov chain
 * (VERBATIM from upstream preload_markov_t)
 * 
 * States:
 *  0: no-a, no-b
 *  1:    a, no-b
 *  2: no-a,    b
 *  3:    a,    b
 */
typedef struct _kp_markov_t
{
    kp_exe_t *a, *b;            /* Involved exes */
    int time;                   /* Total time both exes have been running simultaneously (state 3) */
    double time_to_leave[4];    /* Mean time to leave each state */
    int weight[4][4];           /* Number of times we've gone from state i to state j.
                                 * weight[i][i] is the number of times we have left
                                 * state i. (sum over weight[i][j] for j!=i essentially) */
    
    /* Runtime fields: */
    int state;                  /* Current state */
    int change_timestamp;       /* Time entered the current state */
} kp_markov_t;

#define markov_other_exe(markov,exe) ((markov)->a == (exe) ? (markov)->b : (markov)->a)
#define markov_state(markov) ((exe_is_running((markov)->a)?1:0)+(exe_is_running((markov)->b)?2:0))

/**
 * kp_state_t: Persistent state (the model)
 * (VERBATIM from upstream preload_state_t)
 */
typedef struct _kp_state_t
{
    /* Total seconds that preheat have been running,
     * from the beginning of the persistent state */
    int time;
    
    /* Maps applications known by preheat, indexed by
     * exe name, to a kp_exe_t structure */
    GHashTable *exes;
    
    /* Set of applications that preheat is not interested
     * in. Typically these applications are too small to be
     * a candidate for preloading. Mapped value is the size
     * of the binary (sum of the length of the maps) */
    GHashTable *bad_exes;
    
    /* Set of maps used by known executables, indexed by
     * kp_map_t structures */
    GHashTable *maps;
    
    /* Runtime fields: */
    
    GSList *running_exes;       /* Set of exe structs currently running */
    GPtrArray *maps_arr;        /* Set of maps again, in a sortable array */
    
    int map_seq;                /* Increasing sequence of unique numbers to assign to maps */
    int exe_seq;                /* Increasing sequence of unique numbers to assign to exes */
    
    int last_running_timestamp; /* Last time we checked for processes running */
    int last_accounting_timestamp; /* Last time we did accounting on running times, etc */
    
    gboolean dirty;             /* Whether new scan has been performed since last save */
    gboolean model_dirty;       /* Whether new scan has been performed but no model update yet */
    
    kp_memory_t memstat;        /* System memory stats */
    int memstat_timestamp;      /* Last time we updated memory stats */
    
} kp_state_t;

/* Global state singleton */
extern kp_state_t kp_state[1];

/* State management functions */
void kp_state_load(const char *statefile);
void kp_state_save(const char *statefile);
void kp_state_dump_log(void);
void kp_state_run(const char *statefile);
void kp_state_free(void);
void kp_state_register_exe(kp_exe_t *exe, gboolean create_markovs);
void kp_state_unregister_exe(kp_exe_t *exe);

/* Map management functions */
kp_map_t * kp_map_new(const char *path, size_t offset, size_t length);
void kp_map_free(kp_map_t *map);
void kp_map_ref(kp_map_t *map);
void kp_map_unref(kp_map_t *map);
size_t kp_map_get_size(kp_map_t *map);
guint kp_map_hash(kp_map_t *map);
gboolean kp_map_equal(kp_map_t *a, kp_map_t *b);

/* Exemap management functions */
kp_exemap_t * kp_exemap_new(kp_map_t *map);
void kp_exemap_free(kp_exemap_t *exemap);
void kp_exemap_foreach(GHFunc func, gpointer user_data);

/* Markov management functions */
kp_markov_t * kp_markov_new(kp_exe_t *a, kp_exe_t *b, gboolean initialize);
void kp_markov_free(kp_markov_t *markov, kp_exe_t *from);
void kp_markov_state_changed(kp_markov_t *markov);
double kp_markov_correlation(kp_markov_t *markov);
void kp_markov_foreach(GFunc func, gpointer user_data);

/* Exe management functions */
kp_exe_t * kp_exe_new(const char *path, gboolean running, GSet *exemaps);
void kp_exe_free(kp_exe_t *exe);
kp_exemap_t * kp_exe_map_new(kp_exe_t *exe, kp_map_t *map);

#endif /* STATE_H */
