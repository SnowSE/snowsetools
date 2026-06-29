defmodule SnowSeTools.Scheduling.ScheduleOwnerSchedule do
  @type t :: %__MODULE__{
          owner_key: String.t(),
          type: :professor | :room | :academic_program_semester,
          name: String.t(),
          program_name: String.t() | nil,
          semester_name: String.t() | nil,
          courses: [map()],
          schedule_variants: [map()]
        }

  defstruct [
    :owner_key,
    :type,
    :name,
    :program_name,
    :semester_name,
    :courses,
    :schedule_variants
  ]

  def new(owner_key: owner_key, type: type, name: name, courses: courses) do
    new(owner_key: owner_key, type: type, name: name, courses: courses, opts: [])
  end

  def new(owner_key: owner_key, type: type, name: name, courses: courses, opts: opts) do
    %__MODULE__{
      owner_key: owner_key,
      type: type,
      name: name,
      program_name: opts[:program_name],
      semester_name: opts[:semester_name],
      courses: Enum.uniq_by(courses, & &1["crn"]),
      schedule_variants: opts[:schedule_variants] || []
    }
  end
end
