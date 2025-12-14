/* confkeys.h - Configuration key definitions for Preheat
 *
 * Based on preload 0.6.4 confkeys.h
 * Based on the preload daemon
 * Copyright (C) 2025 Preheat Contributors
 *
 * This file defines all configuration parameters using macros.
 * It's included multiple times with different confkey() definitions.
 */

/* UPSTREAM PARAMETERS (must maintain compatibility) */

/* [model] section */
confkey(model,	integer,	cycle,		     20,	seconds)
confkey(model,	boolean,	usecorrelation,	   true,	-)
confkey(model,	integer,	minsize,	2000000,	bytes)
confkey(model,	integer,	memtotal,	    -10,	signed_integer_percent)
confkey(model,	integer,	memfree,	     50,	signed_integer_percent)
confkey(model,	integer,	memcached,	      0,	signed_integer_percent)

/* [system] section */
confkey(system,	boolean,	doscan,		   true,	-)
confkey(system,	boolean,	dopredict,	   true,	-)
confkey(system,	integer,	autosave,	   3600,	seconds)
confkey(system,	string_list,	mapprefix,	   NULL,	-)
confkey(system,	string_list,	exeprefix,	   NULL,	-)
confkey(system,	integer,	maxprocs,	     30,	processes)
confkey(system,	enum,		sortstrategy,	      3,	-)
confkey(system,	string,		manualapps,	   NULL,	-)

/* KALI EXTENSIONS (opt-in, only active if --enable-kali-extensions) */

#ifdef ENABLE_KALI_EXTENSIONS
/* [kali] section */
confkey(kali,	boolean,	enable_kali_scoring,	false,	-)
confkey(kali,	integer,	kali_tool_boost,	  100,	percent_times_100)
confkey(kali,	boolean,	enable_time_learning,	false,	-)
confkey(kali,	string,		manual_apps_list,	 NULL,	-)
confkey(kali,	string,		blacklist,		 NULL,	-)
#endif
