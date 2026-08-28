import Config
import Dotenvy

source!([
  Path.expand(".env"),
  System.get_env()
])

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

if env!("PHX_SERVER", :boolean, false) do
  config :snow_se_tools, SnowSeToolsWeb.Endpoint, server: true
end

config :snow_se_tools, :oidc,
  issuer: env!("OIDC_ISSUER", :string!),
  client_id: env!("OIDC_CLIENT_ID", :string!),
  redirect_uri: env!("OIDC_REDIRECT_URI", :string, nil),
  idp_hint: env!("OIDC_IDP_HINT", :string, nil)

config :snow_se_tools, :ai,
  endpoint: env!("AI_ENDPOINT", :string!),
  api_key: env!("AI_API_KEY", :string!),
  model: env!("AI_MODEL", :string!)

config :snow_se_tools, SnowSeToolsWeb.Endpoint,
  http: [port: env!("PORT", :integer, 4000), ip: {0, 0, 0, 0}]

if System.get_env("DATABASE_URL") do
  config :snow_se_tools, SnowSeTools.Repo,
    url: env!("DATABASE_URL", :string!),
    pool_size: env!("POOL_SIZE", :integer, 20),
    queue_target: 500,
    queue_interval: 1000
end

if config_env() == :prod do
  secret_key_base = env!("SECRET_KEY_BASE", :string!)
  host = env!("PHX_HOST", :string!)

  config :snow_se_tools, SnowSeToolsWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    secret_key_base: secret_key_base
end
