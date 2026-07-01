<?php
/**
 * Plugin Name: Quant OPcache Reset
 * Description: Resets PHP OPcache when WordPress plugins/themes change so that
 *              admin-driven updates take effect immediately on the current
 *              container. OPcache is configured with revalidate_freq=3600 in
 *              production to minimise EFS metadata I/O; this plugin ensures
 *              admin operations aren't subject to that delay on the container
 *              where the operation happens. Other containers in the same
 *              service will pick up changes within the revalidate_freq window.
 *              For emergency propagation, force a new ECS deployment.
 * Version:     1.0.0
 * Author:      Quant
 */

if (!defined('ABSPATH')) {
    exit;
}

/**
 * Reset PHP OPcache and the realpath cache.
 */
function quant_opcache_reset($context = 'unknown') {
    if (function_exists('opcache_reset')) {
        @opcache_reset();
    }
    if (function_exists('clearstatcache')) {
        clearstatcache(true);
    }
    if (function_exists('error_log')) {
        error_log(sprintf('[quant-opcache] reset triggered: %s', $context));
    }
}

// Plugin lifecycle
add_action('activated_plugin',   function ($plugin) { quant_opcache_reset("activated_plugin:{$plugin}"); });
add_action('deactivated_plugin', function ($plugin) { quant_opcache_reset("deactivated_plugin:{$plugin}"); });
add_action('deleted_plugin',     function ($plugin) { quant_opcache_reset("deleted_plugin:{$plugin}"); });

// Upgrades: core, plugins, themes, translations
add_action('upgrader_process_complete', function ($upgrader, $options) {
    $type = isset($options['type']) ? $options['type'] : 'unknown';
    quant_opcache_reset("upgrader:{$type}");
}, 10, 2);

// Theme switch
add_action('switch_theme', function ($name) { quant_opcache_reset("switch_theme:{$name}"); });

// Customizer saves (can change theme files)
add_action('customize_save_after', function () { quant_opcache_reset('customize_save_after'); });
