defmodule SnowSeTools.AcademicPrograms.SemesterAttrs do
  alias SnowSeTools.AcademicPrograms.CourseAttrs

  @schema Zoi.struct(
            __MODULE__,
            %{
              courses: Zoi.default(Zoi.optional(Zoi.array(CourseAttrs.schema())), [])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end
