<?php

declare(strict_types=1);

return [

    /*
    |--------------------------------------------------------------------------
    | Trusted Proxies
    |--------------------------------------------------------------------------
    |
    | Proxies allowed to set the X-Forwarded-* headers (for example a reverse
    | proxy terminating TLS in front of the application). Use a comma separated
    | list of IP addresses / CIDR ranges, "private_ranges" for all private
    | networks, or "*" to trust the proxy that connects to the application.
    | Leave empty to trust no proxies.
    |
    */

    'proxies' => env('TRUSTED_PROXIES'),

];
