defmodule SnowSeToolsWeb.ModalComponents do
  use Phoenix.Component

  attr :id, :string, required: true
  attr :on_close, :string, required: true
  attr :target, :any, default: nil
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-50 flex items-center justify-center px-4 py-6"
      phx-window-keydown={@on_close}
      phx-key="escape"
      phx-target={@target}
    >
      <button
        type="button"
        aria-label="Close modal"
        phx-click={@on_close}
        phx-target={@target}
        class="absolute inset-0 bg-slate-950/70 backdrop-blur-sm"
      />
      <div class="relative w-full max-w-lg rounded-2xl border border-slate-700 bg-slate-900 p-6 shadow-2xl shadow-slate-950/60">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
