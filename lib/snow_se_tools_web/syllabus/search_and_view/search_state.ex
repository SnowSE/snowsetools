defmodule SnowSeToolsWeb.Syllabus.SearchState do
  import Phoenix.LiveView
  import Phoenix.Component

  defstruct [:key, :query, :selected_term_id, :selected_term_name]

  def assign_component(socket, key, opts \\ []) do
    state = %__MODULE__{
      key: key,
      query: opts[:query] || "",
      selected_term_id: opts[:selected_term_id],
      selected_term_name: opts[:selected_term_name]
    }

    socket
    |> assign(key, state)
    |> maybe_attach_hooks()
  end

  def persist_state(socket) do
    payload = state_payload(socket)
    push_event(socket, "save_state", payload)
  end

  def render(assigns) do
    ~H"""
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SyllabusState">
      export default {
        mounted() {
          const url = new URL(window.location.href);
          if (!url.searchParams.has("q")) {
            try {
              const stored = localStorage.getItem("syllabi_state");
              if (stored) {
                const state = JSON.parse(stored);
                if (state && state.query) {
                  this.pushEvent("restore_state", state);
                }
              }
            } catch (e) {
              console.error("SyllabusState: failed to read localStorage", e);
            }
          }

          this.handleEvent("save_state", (data) => {
            try {
              localStorage.setItem("syllabi_state", JSON.stringify(data));
            } catch (e) {
              console.error("SyllabusState: failed to write localStorage", e);
            }
          });
        }
      }
    </script>
    """
  end

  def hooked_event("restore_state", %{"query" => query} = params, socket)
      when is_binary(query) and byte_size(query) > 0 do
    socket = restore_term(params, socket)

    if pid = socket.assigns.parent_pid do
      send(pid, {:search_navigate, query})
    end

    {:halt, socket}
  end

  def hooked_event("restore_state", _params, socket), do: {:halt, socket}

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  defp maybe_attach_hooks(socket) do
    if hooks_needed?(socket) do
      attach_hook(socket, "search_state:event", :handle_event, &hooked_event/3)
    else
      socket
    end
  end

  defp hooks_needed?(socket) do
    Enum.count(socket.assigns, fn {_, v} -> match?(%__MODULE__{}, v) end) == 1
  end

  defp restore_term(%{"term_id" => term_id}, socket) do
    selected_term_id = normalize_term_id(term_id)

    socket
    |> assign(:selected_term_id, selected_term_id)
    |> assign(
      :selected_term_name,
      find_term_name(socket.assigns.available_terms, selected_term_id)
    )
  end

  defp restore_term(_params, socket), do: socket

  defp state_payload(socket) do
    %{query: socket.assigns.query, term_id: socket.assigns.selected_term_id}
  end

  defp normalize_term_id(term_id) when is_binary(term_id) and byte_size(term_id) == 0, do: nil
  defp normalize_term_id(term_id) when is_binary(term_id), do: term_id
  defp normalize_term_id(_term_id), do: nil

  defp find_term_name(terms, term_id) do
    Enum.find_value(terms, term_id, fn {id, name} ->
      if id == term_id, do: name
    end)
  end
end
