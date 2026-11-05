defmodule SnowSeToolsWeb.Admin.AiSettingsComponent do
  @moduledoc """
  Edits the AI endpoint, model and key that every completion in the app uses.

  The key is write-only: it is stored, but it is never rendered back, so this
  form can say whether an override exists without handing the value to a
  browser. Leaving the key box empty therefore means "keep the key you have",
  not "clear it" -- clearing is the explicit "Use environment value" button.

  "Test AI server" submits the same form, so it tries what is typed, saved or
  not; the result is shown beside the button.
  """

  use SnowSeToolsWeb, :live_component

  alias SnowSeTools.AI.SettingsDomainManager

  def update(%{test_result: result}, socket) do
    {:ok, assign(socket, :test, result)}
  end

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign_new(:test, fn -> nil end)}
  end

  def handle_event("save_ai_settings", %{"ai" => params, "intent" => "test"}, socket) do
    SettingsDomainManager.test_connection(pid: self(), params: params)
    {:noreply, assign(socket, :test, :running)}
  end

  def handle_event("save_ai_settings", %{"ai" => params}, socket) do
    SettingsDomainManager.save_settings(
      pid: self(),
      params: params,
      user: socket.assigns.current_user
    )

    {:noreply, socket}
  end

  def handle_event("clear_ai_override", %{"field" => field}, socket) do
    SettingsDomainManager.clear_override(
      pid: self(),
      field: field,
      user: socket.assigns.current_user
    )

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <section
      id={@id}
      class="min-w-0 rounded-2xl border border-slate-800 bg-slate-900/70 p-4 shadow-xl shadow-slate-950/20 sm:p-5"
    >
      <div class="mb-4 flex items-center justify-between">
        <h2 class="text-lg font-semibold text-slate-100">AI server</h2>
        <span :if={@settings.updated_at} class="text-xs text-slate-400">
          changed by {@settings.updated_by} on {String.slice(@settings.updated_at, 0, 10)}
        </span>
      </div>

      <p class="mb-5 text-sm leading-6 text-slate-300">
        Takes effect on the next completion &mdash; no redeploy. A field left on
        <span class="font-medium text-slate-200">environment</span>
        follows <code class="text-slate-200">prod.env</code>; saving one overrides it until you revert.
      </p>

      <.form
        for={%{}}
        as={:ai}
        id="admin-ai-settings-form"
        phx-submit="save_ai_settings"
        phx-target={@myself}
      >
        <div class="space-y-4">
          <div>
            <div class="mb-1 flex items-center justify-between gap-3">
              <label for="ai-endpoint" class="text-sm font-medium text-slate-200">Endpoint</label>
              <.source_badge
                source={@settings.endpoint_source}
                field="endpoint"
                myself={@myself}
              />
            </div>
            <input
              type="url"
              id="ai-endpoint"
              name="ai[endpoint]"
              value={@settings.endpoint}
              placeholder={@settings.env_endpoint}
              class="w-full rounded-lg border border-slate-700 bg-slate-950/60 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-500"
            />
          </div>

          <div>
            <div class="mb-1 flex items-center justify-between gap-3">
              <label for="ai-model" class="text-sm font-medium text-slate-200">Model</label>
              <.source_badge source={@settings.model_source} field="model" myself={@myself} />
            </div>
            <input
              type="text"
              id="ai-model"
              name="ai[model]"
              value={@settings.model}
              placeholder={@settings.env_model}
              class="w-full rounded-lg border border-slate-700 bg-slate-950/60 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-500"
            />
          </div>

          <div>
            <div class="mb-1 flex items-center justify-between gap-3">
              <label for="ai-api-key" class="text-sm font-medium text-slate-200">API key</label>
              <.source_badge source={@settings.api_key_source} field="api_key" myself={@myself} />
            </div>
            <input
              type="password"
              id="ai-api-key"
              name="ai[api_key]"
              value=""
              autocomplete="off"
              placeholder="unchanged"
              class="w-full rounded-lg border border-slate-700 bg-slate-950/60 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-500"
            />
            <p class="mt-1 text-xs text-slate-400">
              Never shown once saved. Leave blank to keep the current key.
            </p>
          </div>
        </div>

        <div class="mt-5 flex flex-wrap items-center gap-3">
          <button
            type="submit"
            id="ai-settings-save"
            class="rounded-lg bg-emerald-500/90 px-4 py-2 text-sm font-semibold text-emerald-950 transition-colors hover:bg-emerald-400"
          >
            Save AI settings
          </button>
          <button
            type="submit"
            id="ai-settings-test"
            name="intent"
            value="test"
            disabled={@test == :running}
            class="inline-flex items-center gap-2 rounded-lg border border-slate-600 px-4 py-2 text-sm font-semibold text-slate-200 transition-colors hover:border-slate-400 hover:bg-slate-800 disabled:cursor-wait disabled:opacity-60"
          >
            <.icon
              name={if @test == :running, do: "hero-arrow-path", else: "hero-signal"}
              class={if @test == :running, do: "size-4 animate-spin", else: "size-4"}
            /> Test AI server
          </button>
          <.test_result test={@test} />
        </div>
      </.form>
    </section>
    """
  end

  attr :test, :any, required: true

  defp test_result(%{test: nil} = assigns), do: ~H""

  defp test_result(%{test: :running} = assigns) do
    ~H"""
    <span id="ai-settings-test-result" class="text-sm text-slate-400">
      Asking the server for a reply&hellip;
    </span>
    """
  end

  defp test_result(%{test: {status, outcome}} = assigns) do
    assigns = assign(assigns, status: status, outcome: outcome)

    ~H"""
    <div
      id="ai-settings-test-result"
      data-status={@status}
      class={[
        "flex min-w-0 basis-full items-start gap-2 rounded-lg border px-3 py-2 text-sm sm:basis-auto",
        @status == :ok && "border-emerald-500/30 bg-emerald-500/10 text-emerald-200",
        @status == :error && "border-rose-500/30 bg-rose-500/10 text-rose-200"
      ]}
    >
      <.icon
        name={if @status == :ok, do: "hero-check-circle", else: "hero-x-circle"}
        class="mt-0.5 size-4 shrink-0"
      />
      <div class="min-w-0">
        <div class="break-words">{@outcome.message}</div>
        <div class="text-xs opacity-75 break-all">
          {@outcome.model || "no model"} at {@outcome.endpoint || "no endpoint"} &middot; {format_elapsed(
            @outcome.elapsed_ms
          )}
        </div>
      </div>
    </div>
    """
  end

  defp format_elapsed(ms) when ms < 1000, do: "#{ms} ms"
  defp format_elapsed(ms), do: "#{Float.round(ms / 1000, 1)} s"

  attr :source, :atom, required: true
  attr :field, :string, required: true
  attr :myself, :any, required: true

  defp source_badge(assigns) do
    ~H"""
    <%= if @source == :database do %>
      <button
        type="button"
        phx-click="clear_ai_override"
        phx-value-field={@field}
        phx-target={@myself}
        class="text-xs font-medium text-amber-300 underline underline-offset-2 hover:text-amber-200"
      >
        overridden &mdash; use environment value
      </button>
    <% else %>
      <span class="text-xs text-slate-500">environment</span>
    <% end %>
    """
  end
end
