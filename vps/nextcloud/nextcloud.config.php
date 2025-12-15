<?php
$CONFIG = array (
  'trusted_proxies' => array(
    0 => '172.16.0.0/12',
  ),
  'forwarded_for_headers' => array(
    0 => 'HTTP_X_FORWARDED_FOR',
  ),
  'maintenance_window_start' => 2,
  'default_phone_region' => 'NL',

  // Memory caching configuration
  'memcache.local' => '\\OC\\Memcache\\APCu',
  'memcache.distributed' => '\\OC\\Memcache\\Redis',
  'memcache.locking' => '\\OC\\Memcache\\Redis',
  'redis' => array(
    'host' => 'redis',
    'port' => 6379,
    'password' => getenv('REDIS_HOST_PASSWORD'),
  ),

  // Performance optimizations
  'filelocking.enabled' => true,
  'log_query' => false,
  'loglevel' => 2,

  // Preview generation optimization - limit to common formats
  'enabledPreviewProviders' => array(
    'OC\\Preview\\PNG',
    'OC\\Preview\\JPEG',
    'OC\\Preview\\GIF',
    'OC\\Preview\\HEIC',
    'OC\\Preview\\BMP',
    'OC\\Preview\\XBitmap',
    'OC\\Preview\\MP3',
    'OC\\Preview\\TXT',
    'OC\\Preview\\MarkDown',
  ),

  // Database optimizations
  'dbdriveroptions' => array(
    'PDO::ATTR_TIMEOUT' => 30,
  ),
);
