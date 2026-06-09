defmodule SimpleSyllabusReporter.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = base_children() ++ conditional_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SimpleSyllabusReporter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp base_children do
    [
      {Oidcc.ProviderConfiguration.Worker,
       %{
         issuer:
           Application.fetch_env!(:simple_syllabus_reporter, :oidc) |> Keyword.fetch!(:issuer),
         name: SimpleSyllabusReporter.OidcProvider,
         provider_configuration_opts: %{
           quirks: %{
             document_overrides: %{
               # Disable PAR - oidcc attempts PAR whenever the endpoint is present,
               # which fails for public (PKCE) clients against Keycloak's token endpoint.
               "pushed_authorization_request_endpoint" => :undefined,
               "require_pushed_authorization_requests" => false,
               # Keycloak doesn't advertise "none" in token_endpoint_auth_methods_supported,
               # but public clients (PKCE, no secret) require it to authenticate with just client_id.
               "token_endpoint_auth_methods_supported" => [
                 "private_key_jwt",
                 "client_secret_basic",
                 "client_secret_post",
                 "tls_client_auth",
                 "client_secret_jwt",
                 "none"
               ]
             }
           }
         }
       }},
      SimpleSyllabusReporterWeb.Telemetry,
      {DNSCluster,
       query: Application.get_env(:simple_syllabus_reporter, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SimpleSyllabusReporter.PubSub},
      SimpleSyllabusReporterWeb.Endpoint
    ]
  end

  defp conditional_children do
    # Only start database-dependent services if DATABASE_URL is configured
    if System.get_env("DATABASE_URL") do
      [
        SimpleSyllabusReporter.Repo,
        SimpleSyllabusReporter.AI.AsyncCompletions,
        SimpleSyllabusReporter.Cache,
        SimpleSyllabusReporter.Reports.ReportGeneratorDomainManger,
        SimpleSyllabusReporter.Syllabi.Syncing.SyllabusScraperAgent
      ]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SimpleSyllabusReporterWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
