defmodule SnowSeTools.Curriculum.CurriculumData do
  @moduledoc """
  Everything the curriculum pages draw, read in one go. The whole map is a few
  hundred rows, so pages reload all of it on any change rather than tracking
  which piece moved.
  """

  alias SnowSeTools.Curriculum.{AbetDb, OutcomeDb, SkillDb, SuggestionDb}

  def load do
    with {:ok, skills} <- SkillDb.list_skills(),
         {:ok, dependencies} <- SkillDb.list_dependencies(),
         {:ok, links} <- SkillDb.list_course_skills(),
         {:ok, master_syllabi} <- OutcomeDb.list_master_syllabi(),
         {:ok, outcomes} <- OutcomeDb.list_outcomes(),
         {:ok, abet_outcomes} <- AbetDb.list_outcomes(),
         {:ok, coverage} <- AbetDb.list_coverage(),
         {:ok, last_import} <- AbetDb.last_import(),
         {:ok, pending} <- SuggestionDb.list_pending() do
      {:ok,
       %{
         skills: skills,
         dependencies: dependencies,
         links: links,
         master_syllabi: master_syllabi,
         outcomes: outcomes,
         abet_outcomes: abet_outcomes,
         coverage: coverage,
         last_import: last_import,
         pending: pending
       }}
    end
  end

  @doc "The parts of the map a review needs to tell new from known."
  def review_state do
    with {:ok, skills} <- SkillDb.list_skills(),
         {:ok, dependencies} <- SkillDb.list_dependencies(),
         {:ok, links} <- SkillDb.list_course_skills(),
         {:ok, rejected} <- SuggestionDb.rejected_fingerprints() do
      {:ok, %{skills: skills, dependencies: dependencies, links: links, rejected: rejected}}
    end
  end
end
