<?php

use App\Models\User;
use App\Services\OAuth\KeycloakProvider;
use App\Services\OAuth\VatsimProvider;
use League\OAuth2\Client\Provider\GenericResourceOwner;
use League\OAuth2\Client\Token\AccessToken;
use Tests\TestCase;

/**
 * Builds a stub KeycloakProvider returning the given userinfo claims.
 *
 * @param  array<string, mixed>  $claims
 */
function fakeKeycloakProvider(array $claims): KeycloakProvider
{
    /** @var KeycloakProvider&\Mockery\MockInterface $provider */
    $provider = Mockery::mock(KeycloakProvider::class);
    $provider->allows('getAccessToken')->andReturn(new AccessToken([
        'access_token' => 'fake-access-token',
        'refresh_token' => 'fake-refresh-token',
        'expires_in' => 3600,
    ]));
    $provider->allows('getResourceOwner')->andReturn(new GenericResourceOwner($claims, 'sub'));
    $provider->allows('getOAuthProperty')->andReturnUsing(
        fn (string $property, mixed $data): mixed => (new KeycloakProvider())->getOAuthProperty($property, $data)
    );

    return $provider;
}

it('binds the Keycloak provider when configured', function (): void {
    $base = 'https://kc.test/realms/r/protocol/openid-connect';
    config(['oauth.provider' => 'keycloak', 'oauth.base' => $base]);

    $provider = resolve(VatsimProvider::class);

    expect($provider)->toBeInstanceOf(KeycloakProvider::class)
        ->and($provider->getBaseAuthorizationUrl())->toBe($base . '/auth')
        ->and($provider->getBaseAccessTokenUrl([]))->toBe($base . '/token')
        ->and($provider->getResourceOwnerDetailsUrl(new AccessToken(['access_token' => 'x'])))->toBe($base . '/userinfo');
});

it('keeps the VATSIM provider by default', function (): void {
    config(['oauth.provider' => 'vatsim']);

    expect(resolve(VatsimProvider::class))->not->toBeInstanceOf(KeycloakProvider::class);
});

it('logs in a user from Keycloak userinfo claims', function (): void {
    /** @var TestCase $this */
    auth()->logout();

    config([
        'oauth.provider' => 'keycloak',
        'oauth.mapping_cid' => 'preferred_username',
        'oauth.mapping_first_name' => 'given_name',
        'oauth.mapping_last_name' => 'family_name',
        'oauth.mapping_mail' => 'email',
    ]);

    $this->instance(VatsimProvider::class, fakeKeycloakProvider([
        'sub' => 'f1c3a2b4-uuid',
        'preferred_username' => '1234567',
        'given_name' => 'Jean',
        'family_name' => 'Dupont',
        'email' => 'jean@example.org',
    ]));

    $this->withSession(['oauthstate' => 's'])
        ->get(route('login', ['code' => 'c', 'state' => 's']))
        ->assertRedirect(route('home'));

    $user = User::find(1234567);

    expect($user)->not->toBeNull()
        ->and($user->name_first)->toBe('Jean')
        ->and($user->name_last)->toBe('Dupont')
        ->and($user->email)->toBe('jean@example.org');
    $this->assertAuthenticatedAs($user);
});
