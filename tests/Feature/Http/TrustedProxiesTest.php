<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

beforeEach(function (): void {
    Route::get('/_testing/trusted-proxies', fn (Request $request): array => [
        'secure' => $request->isSecure(),
        'ip' => $request->ip(),
        'host' => $request->getHost(),
    ]);
});

/**
 * @return array<string, string>
 */
function forwardedHeaders(): array
{
    return [
        'X-Forwarded-For' => '203.0.113.10',
        'X-Forwarded-Proto' => 'https',
        'X-Forwarded-Host' => 'booking.example.org',
        'X-Forwarded-Port' => '443',
    ];
}

it('ignores forwarded headers when no proxies are trusted', function (): void {
    /** @var TestCase $this */
    config(['trustedproxy.proxies' => null]);

    $this->withServerVariables(['REMOTE_ADDR' => '10.0.0.5'])
        ->getJson('/_testing/trusted-proxies', forwardedHeaders())
        ->assertOk()
        ->assertJson(['secure' => false, 'ip' => '10.0.0.5']);
});

it('honours forwarded headers from a trusted proxy', function (string $proxies): void {
    /** @var TestCase $this */
    config(['trustedproxy.proxies' => $proxies]);

    $this->withServerVariables(['REMOTE_ADDR' => '10.0.0.5'])
        ->getJson('/_testing/trusted-proxies', forwardedHeaders())
        ->assertOk()
        ->assertJson(['secure' => true, 'ip' => '203.0.113.10', 'host' => 'booking.example.org']);
})->with([
    'private ranges' => 'private_ranges',
    'cidr list' => '192.168.0.0/16, 10.0.0.0/8',
    'wildcard' => '*',
]);

it('ignores forwarded headers from an untrusted proxy', function (): void {
    /** @var TestCase $this */
    config(['trustedproxy.proxies' => '192.168.0.0/16']);

    $this->withServerVariables(['REMOTE_ADDR' => '10.0.0.5'])
        ->getJson('/_testing/trusted-proxies', forwardedHeaders())
        ->assertOk()
        ->assertJson(['secure' => false, 'ip' => '10.0.0.5']);
});
