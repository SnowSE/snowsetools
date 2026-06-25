defmodule SnowSeTools.Scheduling.ScheduleOwnerMetadata do
  @schema Zoi.struct(
            __MODULE__,
            %{
              type: Zoi.atom(),
              name: Zoi.string(),
              academic_program_id: Zoi.integer() || nil,
              academic_program_semester: Zoi.integer() || nil,
              key: Zoi.string()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end
