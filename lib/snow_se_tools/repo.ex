defmodule SnowSeTools.Repo do
  use Ecto.Repo,
    otp_app: :snow_se_tools,
    adapter: Ecto.Adapters.Postgres
end
