defmodule SnowSeTools.AcademicPrograms.CourseAttrs do
  @schema Zoi.struct(
            __MODULE__,
            %{
              subject_code: Zoi.string(),
              course_number: Zoi.string()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end
