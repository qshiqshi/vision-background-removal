/*
 * OBS Background Removal Plugin for macOS
 * Video Filter Interface
 * Copyright (C) 2026 Andreas Kuschner
 */

#ifndef BACKGROUND_REMOVAL_FILTER_H
#define BACKGROUND_REMOVAL_FILTER_H

#ifdef __cplusplus
extern "C" {
#endif

#include <obs-module.h>

// Filter settings keys
#define SETTING_ENABLED "enabled"
#define SETTING_QUALITY "quality"
#define SETTING_BACKGROUND_MODE "background_mode"
#define SETTING_BLUR_RADIUS "blur_radius"
#define SETTING_EDGE_SMOOTHING "edge_smoothing"
#define SETTING_MASK_THRESHOLD "mask_threshold"
#define SETTING_TEMPORAL_SMOOTHING "temporal_smoothing"
#define SETTING_TEMPORAL_FACTOR "temporal_factor"
#define SETTING_EDGE_REFINEMENT "edge_refinement"
#define SETTING_BG_COLOR "background_color"
#define SETTING_SHOW_MASK "show_mask"
#define SETTING_PERFORMANCE_INFO "performance_info"

// Quality options
#define QUALITY_FAST 0
#define QUALITY_BALANCED 1
#define QUALITY_ACCURATE 2

// Background mode options
#define BG_MODE_BLUR 0
#define BG_MODE_COLOR 1
#define BG_MODE_TRANSPARENT 2
#define BG_MODE_IMAGE 3

// Filter source info (declared in implementation)
extern struct obs_source_info background_removal_filter_info;

#ifdef __cplusplus
}
#endif

#endif // BACKGROUND_REMOVAL_FILTER_H
