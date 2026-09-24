<?php

namespace App\Services\OAuth;

use League\OAuth2\Client\Provider\GenericProvider;

class KeycloakProvider extends VatsimProvider
{
    /**
     * Initializes the provider against a Keycloak realm's OpenID Connect endpoints.
     * `oauth.base` must be the realm's `/protocol/openid-connect` URL.
     */
    public function __construct()
    {
        GenericProvider::__construct([
            'clientId'                => config('oauth.id'),
            'clientSecret'            => config('oauth.secret'),
            'redirectUri'             => route('login'),
            'urlAuthorize'            => config('oauth.base') . '/auth',
            'urlAccessToken'          => config('oauth.base') . '/token',
            'urlResourceOwnerDetails' => config('oauth.base') . '/userinfo',
            'scopes'                  => config('oauth.scopes'),
            'scopeSeparator'          => ' ',
        ]);
    }
}
