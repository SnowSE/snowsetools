defmodule SnowSeTools.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = base_children() ++ conditional_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SnowSeTools.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp base_children do
    oidc_children() ++
      [
        SnowSeToolsWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:snow_se_tools, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: SnowSeTools.PubSub},
        SnowSeToolsWeb.Endpoint
      ]
  end

  defp conditional_children do
    # Only start database-dependent services if DATABASE_URL is configured
    if System.get_env("DATABASE_URL") do
      db_children =
        [
          SnowSeTools.Repo,
          SnowSeTools.Cache,
          db_domain_children()
        ]
        |> List.flatten()
        |> Enum.reject(&is_nil/1)

      db_children ++ [SnowSeTools.AI.AsyncCompletions]
    else
      []
    end
  end

  defp oidc_children do
    if mock_external_dependencies?() do
      []
    else
      [
        {Oidcc.ProviderConfiguration.Worker,
         %{
           issuer: Application.fetch_env!(:snow_se_tools, :oidc) |> Keyword.fetch!(:issuer),
           name: SnowSeTools.OidcProvider,
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
         }}
      ]
    end
  end

  defp db_domain_children do
    if Application.get_env(:snow_se_tools, :start_db_domain_children?, true) do
      [
        SnowSeTools.UserGroups.UserGroupDomainManager,
        SnowSeTools.Snow.SnowCourseCacheDomainManager,
        SnowSeTools.AcademicPrograms.ProgramDomainManager,
        SnowSeTools.Scheduling.ScheduleOwnerDomainManager,
        SnowSeTools.Scheduling.ScheduleChangeDomainManager,
        SnowSeTools.Reports.ReportGeneratorDomainManger,
        SnowSeTools.Syllabi.Syncing.SyllabusScraperAgent
      ]
    else
      []
    end
  end

  defp mock_external_dependencies? do
    Application.get_env(:snow_se_tools, :mock_external_dependencies?, false)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SnowSeToolsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
