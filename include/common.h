/* common.h - Common includes and definitions for Preheat
 *
 * Based on preload 0.6.4
 * Based on the preload daemon
 * Copyright (C) 2025 Preheat Contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#ifndef COMMON_H
#define COMMON_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>

#include <glib.h>

/* Compatibility macros */
#ifndef G_GNUC_UNUSED
#define G_GNUC_UNUSED __attribute__((__unused__))
#endif

/* Signal handling return type */
#ifndef RETSIGTYPE
#define RETSIGTYPE void
#endif

#endif /* COMMON_H */
