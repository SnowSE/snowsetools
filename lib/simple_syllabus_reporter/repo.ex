defmodule SimpleSyllabusReporter.Repo do
  use Ecto.Repo,
    otp_app: :simple_syllabus_reporter,
    adapter: Ecto.Adapters.Postgres
end
