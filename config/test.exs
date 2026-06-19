import Config

System.put_env(
  "DATABASE_URL",
  System.get_env("DATABASE_URL") ||
    "ecto://syllabus_test_user:syllabus_test_pass@localhost:5433/snow_se_tools_test"
)

System.put_env(
  "OIDC_ISSUER",
  System.get_env("OIDC_ISSUER") || "http://localhost:5556/realms/test"
)

System.put_env("OIDC_CLIENT_ID", System.get_env("OIDC_CLIENT_ID") || "snow-se-tools-test")
System.put_env("AI_ENDPOINT", System.get_env("AI_ENDPOINT") || "http://localhost:5557")
System.put_env("AI_API_KEY", System.get_env("AI_API_KEY") || "test-api-key")
System.put_env("AI_MODEL", System.get_env("AI_MODEL") || "test-model")

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :snow_se_tools, SnowSeToolsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "MxJlN/focNzVRl/22870oWk+cubOB3gmOTTdZQpmTptLbe4h3v73wkyYCt93fRpK",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :snow_se_tools, SnowSeTools.Repo,
  url: System.fetch_env!("DATABASE_URL"),
  pool_size: 5

config :snow_se_tools,
  mock_external_dependencies?: true,
  start_db_domain_children?: false
