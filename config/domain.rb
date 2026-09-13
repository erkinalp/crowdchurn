# frozen_string_literal: true

# CrowdChurn is a fork of Gumroad - https://github.com/antiwork/gumroad
# Domain configuration for self-hosted instances
# bin/dev-lane exports DEV_LANE_PORT per lane; without it every absolute URL a
# nonzero lane generates (mailer links, *_url helpers, cross-subdomain redirects)
# would point at lane 0's :3000. Port-less entries (valid_discover_host, the bare
# valid_request_hosts) must stay port-less — they are compared against
# request.host, which never carries a port.
dev_lane_port = ENV.fetch("DEV_LANE_PORT", "3000")

configuration_by_env = {
  production: {
    protocol: "https",
    domain: "example.com",
    asset_domain: "assets.example.com",
    root_domain: "example.com",
    short_domain: "example.com",
    discover_domain: "example.com",
    api_domain: "api.example.com",
    third_party_analytics_domain: "analytics.example.com",
    valid_request_hosts: ["example.com", "app.example.com"],
    valid_api_request_hosts: ["api.example.com"],
    valid_discover_host: "example.com",
    valid_cors_origins: ["example.com"],
    internal_domain: "internal.example.com",
    default_email_domain: "example.com",
    anycable_host: "cable.example.com",
  },
  staging: {
    protocol: "https",
    domain: "staging.example.com",
    asset_domain: "staging-assets.example.com",
    root_domain: "staging.example.com",
    short_domain: "staging.example.com",
    discover_domain: "staging.example.com",
    api_domain: "api.staging.example.com",
    third_party_analytics_domain: "staging.analytics.example.com",
    valid_request_hosts: ["staging.example.com", "app.staging.example.com"],
    valid_api_request_hosts: ["api.staging.example.com"],
    valid_discover_host: "staging.example.com",
    valid_cors_origins: ["staging.example.com"],
    internal_domain: "internal.example.com",
    default_email_domain: "staging.example.com",
    anycable_host: "cable.staging.example.com",
  },
  test: {
    protocol: "http",
    domain: "app.test.example.com:31337",
    asset_domain: "test.example.com:31337",
    root_domain: "test.example.com:31337",
    short_domain: "short-domain.test.example.com:31337",
    discover_domain: "test.example.com:31337",
    api_domain: "api.test.example.com:31337",
    third_party_analytics_domain: "analytics.test.example.com",
    valid_request_hosts: ["127.0.0.1", "app.test.example.com", "test.example.com"],
    valid_api_request_hosts: ["api.test.example.com"],
    valid_discover_host: "test.example.com",
    valid_cors_origins: ["help.test.example.com", "customers.test.example.com"],
    internal_domain: "test.internal.example.com",
    default_email_domain: "test.example.com", # unused
    anycable_host: "cable.test.example.com",
  },
  development: {
    protocol: "http",
    domain: "localhost:#{dev_lane_port}",
    asset_domain: "app.localhost:#{dev_lane_port}",
    root_domain: "localhost:#{dev_lane_port}",
    short_domain: "s.localhost:#{dev_lane_port}",
    discover_domain: "localhost:#{dev_lane_port}",
    api_domain: "api.localhost:#{dev_lane_port}",
    third_party_analytics_domain: "analytics.localhost:#{dev_lane_port}",
    valid_request_hosts: ["app.localhost", "localhost", "app.localhost:#{dev_lane_port}", "localhost:#{dev_lane_port}"],
    valid_api_request_hosts: ["api.localhost", "api.localhost:#{dev_lane_port}"],
    valid_discover_host: "localhost",
    valid_cors_origins: [],
    internal_domain: "internal.localhost",
    default_email_domain: "staging.example.com",
    anycable_host: "cable.localhost",
  }
}

# bin/vite requires this file before Rails boots, so ActiveSupport is not loaded here. Keep every
# check below to plain Ruby: `present?` and `presence` raise NoMethodError in that path.
custom_domain       = ENV["CUSTOM_DOMAIN"]
custom_short_domain = ENV["CUSTOM_SHORT_DOMAIN"]
custom_protocol     = ENV["CUSTOM_PROTOCOL"].to_s.strip
environment         = ENV["RAILS_ENV"]&.to_sym || :development
config              = configuration_by_env[environment]

# CUSTOM_PROTOCOL pairs with CUSTOM_DOMAIN for local HTTPS. Without it the scheme stays "http", so
# pages the mobile app embeds in an HTTPS WebView fail silently on their assets. Blank or
# whitespace-only falls back: an empty scheme yields URLs like "://gumroad.com".
PROTOCOL            = custom_protocol.empty? ? config[:protocol] : custom_protocol
DOMAIN              = custom_domain || config[:domain]
ASSET_DOMAIN        = ENV["ASSET_DOMAIN"] || config[:asset_domain]
ROOT_DOMAIN         = custom_domain || config[:root_domain]
SHORT_DOMAIN        = custom_short_domain || config[:short_domain]
API_DOMAIN          = config[:api_domain]
THIRD_PARTY_ANALYTICS_DOMAIN = config[:third_party_analytics_domain]
VALID_REQUEST_HOSTS = config[:valid_request_hosts]
VALID_API_REQUEST_HOSTS = config[:valid_api_request_hosts]
VALID_CORS_ORIGINS = config[:valid_cors_origins]
INTERNAL_DOMAIN = config[:internal_domain]
DEFAULT_EMAIL_DOMAIN    = config[:default_email_domain]
ANYCABLE_HOST           = config[:anycable_host]

if custom_domain
  VALID_REQUEST_HOSTS << custom_domain
  VALID_API_REQUEST_HOSTS << "api.#{custom_domain}"
  VALID_API_REQUEST_HOSTS << custom_domain unless ENV["BRANCH_DEPLOYMENT"].to_s.empty? # Allow CORS to preview app's root domain
  VALID_CORS_ORIGINS << custom_domain
  DISCOVER_DOMAIN = custom_domain
  VALID_DISCOVER_REQUEST_HOST = custom_domain
else
  DISCOVER_DOMAIN = config[:discover_domain]
  VALID_DISCOVER_REQUEST_HOST = config[:valid_discover_host]
end

if environment == :development && !ENV["LOCAL_PROXY_DOMAIN"].nil?
  VALID_REQUEST_HOSTS << ENV["LOCAL_PROXY_DOMAIN"].sub(/https?:\/\//, "")
end
