/*
 * OBS Background Removal Plugin for macOS
 * Copyright (C) 2026 Andreas Kuschner
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 */

#ifndef PLUGIN_MAIN_H
#define PLUGIN_MAIN_H

#ifdef __cplusplus
extern "C" {
#endif

#include <obs-module.h>

#define PLUGIN_NAME "vision-background-removal"
#define PLUGIN_VERSION "1.0.0"

// Filter registration
extern struct obs_source_info background_removal_filter_info;

#ifdef __cplusplus
}
#endif

#endif // PLUGIN_MAIN_H
