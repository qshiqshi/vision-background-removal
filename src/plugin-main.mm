/*
 * OBS Background Removal Plugin for macOS
 * Copyright (C) 2026 Andreas Kuschner
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 */

#import <Foundation/Foundation.h>
#include "plugin-main.h"
#include "background-removal-filter.h"

OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE(PLUGIN_NAME, "en-US")

MODULE_EXPORT const char *obs_module_name(void)
{
    return "Vision Background Removal";
}

MODULE_EXPORT const char *obs_module_description(void)
{
    return "Real-time background removal using Apple Vision Framework. "
           "Optimized for Apple Silicon with hardware acceleration.";
}

bool obs_module_load(void)
{
    blog(LOG_INFO, "[Background Removal] Loading plugin version %s", PLUGIN_VERSION);
    blog(LOG_INFO, "[Background Removal] Using Apple Vision Framework for person segmentation");

    // Check if running on Apple Silicon
    #if defined(__arm64__) || defined(__aarch64__)
        blog(LOG_INFO, "[Background Removal] Running on Apple Silicon - optimal performance enabled");
    #else
        blog(LOG_WARNING, "[Background Removal] Running on Intel - performance may be reduced");
    #endif

    // Register the video filter
    obs_register_source(&background_removal_filter_info);

    blog(LOG_INFO, "[Background Removal] Plugin loaded successfully");
    return true;
}

void obs_module_unload(void)
{
    blog(LOG_INFO, "[Background Removal] Plugin unloaded");
}

MODULE_EXPORT const char *obs_module_author(void)
{
    return "Andreas Kuschner";
}
