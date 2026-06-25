defmodule SnowSeToolsWeb.ModalComponents do
  use Phoenix.Component

  attr :id, :string, required: true
  attr :on_close, :string, required: true
  attr :target, :any, default: nil
  attr :x, :integer, default: nil
  attr :y, :integer, default: nil
  attr :panel_class, :string, default: nil
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class={modal_container_class(x: @x, y: @y)}
      phx-window-keydown={@on_close}
      phx-key="escape"
      phx-target={@target}
    >
      <button
        type="button"
        aria-label="Close modal"
        phx-click={@on_close}
        phx-target={@target}
        class={backdrop_class(x: @x, y: @y)}
      />
      <div
        class={panel_class(panel_class: @panel_class, x: @x, y: @y)}
        style={panel_style(x: @x, y: @y)}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp modal_container_class(x: nil, y: nil),
    do: "fixed inset-0 z-50 flex items-center justify-center px-4 py-6"

  defp modal_container_class(x: x, y: y) when is_integer(x) and is_integer(y),
    do: "fixed inset-0 z-50"

  defp backdrop_class(x: nil, y: nil), do: "absolute inset-0 bg-slate-950/70 backdrop-blur-sm"
  defp backdrop_class(x: x, y: y) when is_integer(x) and is_integer(y), do: "absolute inset-0"

  defp panel_class(panel_class: nil, x: nil, y: nil),
    do:
      "relative w-full max-w-lg rounded-2xl border border-slate-700 bg-slate-900 p-6 shadow-2xl shadow-slate-950/60"

  defp panel_class(panel_class: nil, x: x, y: y) when is_integer(x) and is_integer(y),
    do: "fixed rounded-md border border-slate-700 bg-slate-950 shadow-2xl shadow-slate-950/60"

  defp panel_class(panel_class: panel_class, x: _x, y: _y), do: panel_class

  defp panel_style(x: nil, y: nil), do: nil

  defp panel_style(x: x, y: y) when is_integer(x) and is_integer(y),
    do: "left: #{x}px; top: #{y}px"
end
