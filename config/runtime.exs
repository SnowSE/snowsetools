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
  config :simple_syllabus_reporter, SimpleSyllabusReporterWeb.Endpoint, server: true
end

config :simple_syllabus_reporter, :oidc,
  issuer: env!("OIDC_ISSUER", :string!),
  client_id: env!("OIDC_CLIENT_ID", :string!)

config :simple_syllabus_reporter, :ai,
  endpoint: env!("AI_ENDPOINT", :string!),
  api_key: env!("AI_API_KEY", :string!),
  model: env!("AI_MODEL", :string!)

config :simple_syllabus_reporter, SimpleSyllabusReporterWeb.Endpoint,
  http: [port: env!("PORT", :integer, 4000), ip: {0, 0, 0, 0}]

if config_env() == :test do
  config :simple_syllabus_reporter, SimpleSyllabusReporter.Repo,
    url: env!("DATABASE_URL", :string!),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: env!("POOL_SIZE", :integer, 5)
else
  config :simple_syllabus_reporter, SimpleSyllabusReporter.Repo,
    url: env!("DATABASE_URL", :string!),
    pool_size: env!("POOL_SIZE", :integer, 10)
end

if config_env() == :prod do
  secret_key_base = env!("SECRET_KEY_BASE", :string!)
  host = env!("PHX_HOST", :string, "example.com")

  config :simple_syllabus_reporter, SimpleSyllabusReporterWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base
end
