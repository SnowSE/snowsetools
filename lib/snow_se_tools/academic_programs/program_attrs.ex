defmodule SnowSeTools.AcademicPrograms.ProgramAttrs do
  alias SnowSeTools.AcademicPrograms.SemesterAttrs

  @schema Zoi.struct(
            __MODULE__,
            %{
              name: Zoi.string(),
              semesters: Zoi.default(Zoi.optional(Zoi.array(SemesterAttrs.schema())), [])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def parse(value) do
    case Zoi.parse(@schema, value) do
      {:ok, program} ->
        {:ok, program}

      {:error, errors} ->
        {:error, "Invalid academic program payload: #{inspect(Zoi.treefy_errors(errors))}"}
    end
  end
end
