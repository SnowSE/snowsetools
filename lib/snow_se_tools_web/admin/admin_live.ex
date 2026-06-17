defmodule SnowSeToolsWeb.Admin.AdminLive do
  use SnowSeToolsWeb, :live_view
  use SnowSeToolsWeb.Admin.AdminUIMessages
  use SnowSeToolsWeb.Admin.AdminSnowCoursesUIMessages

  alias SnowSeTools.Snow.SnowCourseCacheDomainManager
  alias SnowSeTools.UserGroups.UserGroupDomainManager
  alias SnowSeToolsWeb.UserAuth

  on_mount {UserAuth, :ensure_admin}

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin")
      |> assign(:users, [])
      |> assign(:groups, [])
      |> assign(:editing_group_id, nil)
      |> assign(:last_action_message, nil)
      |> assign(:pending_delete, nil)
      |> assign(:group_form, to_form(%{"name" => ""}, as: :group))
      |> assign(:user_form, to_form(%{"email" => ""}, as: :user))

    if connected?(socket) do
      UserGroupDomainManager.request_dashboard(pid: self())
      SnowCourseCacheDomainManager.request_dashboard(pid: self())
    end

    {:ok, socket}
  end

  def handle_event("create_user", %{"user" => user_params}, socket) do
    UserGroupDomainManager.create_user(pid: self(), user_params: user_params)
    {:noreply, socket}
  end

  def handle_event("save_group", %{"group" => group_params}, socket) do
    if socket.assigns.editing_group_id do
      UserGroupDomainManager.update_group(
        pid: self(),
        group_id: socket.assigns.editing_group_id,
        group_params: group_params
      )
    else
      UserGroupDomainManager.create_group(pid: self(), group_params: group_params)
    end

    {:noreply, socket}
  end

  def handle_event("edit_group", %{"id" => group_id}, socket) do
    group = Enum.find(socket.assigns.groups, &(&1.id == group_id))

    form_params = %{
      "name" => if(group, do: group.name, else: "")
    }

    {:noreply,
     socket
     |> assign(:editing_group_id, group_id)
     |> assign(:group_form, to_form(form_params, as: :group))}
  end

  def handle_event("cancel_group_edit", _params, socket) do
    {:noreply, reset_group_form(socket)}
  end

  def handle_event("request_delete_group", %{"id" => group_id}, socket) do
    group = Enum.find(socket.assigns.groups, &(&1.id == group_id))

    pending_delete =
      if group do
        %{kind: :group, id: group.id, label: group.name}
      else
        nil
      end

    {:noreply, assign(socket, :pending_delete, pending_delete)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :pending_delete, nil)}
  end

  def handle_event("confirm_delete", _params, socket) do
    case socket.assigns.pending_delete do
      %{kind: :group, id: group_id} ->
        UserGroupDomainManager.delete_group(pid: self(), group_id: group_id)

      _ ->
        :ok
    end

    {:noreply, assign(socket, :pending_delete, nil)}
  end

  def handle_event("add_user_group", %{"user_id" => user_id, "group_id" => group_id}, socket) do
    UserGroupDomainManager.add_user_group(pid: self(), user_id: user_id, group_id: group_id)
    {:noreply, socket}
  end

  def handle_event("remove_user_group", %{"user_id" => user_id, "group_id" => group_id}, socket) do
    UserGroupDomainManager.remove_user_group(pid: self(), user_id: user_id, group_id: group_id)
    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <div class="mx-auto max-w-[1800px] px-4 py-6">
        <div class="mb-6 flex items-end justify-between gap-4">
          <div class="space-y-2">
            <h1 class="text-3xl font-semibold text-slate-100">User and group management</h1>
          </div>
        </div>

        <div class="grid gap-6 xl:grid-cols-[1fr_1.2fr]">
          <%= if @last_action_message do %>
            <div class="col-span-full rounded-xl border border-emerald-500/20 bg-emerald-500/10 px-4 py-3 text-sm font-medium text-emerald-200">
              {@last_action_message}
            </div>
          <% end %>
          <section class="rounded-2xl border border-slate-800 bg-slate-900/70 p-5 shadow-xl shadow-slate-950/20">
            <div class="mb-4 flex items-center justify-between">
              <h2 class="text-lg font-semibold text-slate-100">Users</h2>
            </div>

            <.form for={@user_form} id="admin-user-form" phx-submit="create_user" class="mb-5">
              <div class="flex flex-col gap-3 sm:flex-row">
                <label class="flex-1 space-y-2">
                  <span class="block text-sm font-medium text-slate-300">Create user</span>
                  <input
                    type="email"
                    name={@user_form[:email].name}
                    value={@user_form[:email].value}
                    placeholder="user@example.com"
                    class="w-full rounded-xl border border-slate-700 bg-slate-950/60 px-4 py-3 text-slate-100 placeholder:text-slate-500 outline-none transition focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20"
                  />
                </label>
                <button
                  type="submit"
                  class="rounded-xl bg-indigo-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-indigo-400"
                >
                  Add User
                </button>
              </div>
            </.form>

            <div class="space-y-3">
              <%= for user <- @users do %>
                <article class="rounded-2xl border border-slate-800 bg-slate-950/50 p-4">
                  <div class="flex flex-wrap items-start justify-between gap-4">
                    <div>
                      <div class="flex items-center gap-2">
                        <h3 class="font-medium text-slate-100">{user.email}</h3>
                        <%= if user_in_admin_group?(@groups, user.group_ids) do %>
                          <span class="rounded-full bg-emerald-500/15 px-2 py-0.5 text-[11px] font-medium text-emerald-300">
                            admin
                          </span>
                        <% end %>
                      </div>
                      <p class="mt-1 text-xs text-slate-500">User ID: {user.id}</p>
                      <div class="mt-3 flex flex-wrap gap-2">
                        <%= if user.group_ids == [] do %>
                          <span class="text-sm text-slate-500">No groups assigned</span>
                        <% else %>
                          <%= for group <- groups_for_user(@groups, user.group_ids) do %>
                            <span class={[
                              "rounded-full px-2.5 py-1 text-xs font-medium",
                              group.name == "admin" &&
                                "bg-emerald-500/15 text-emerald-300",
                              group.name != "admin" &&
                                "bg-slate-800 text-slate-300"
                            ]}>
                              {group.name}
                            </span>
                          <% end %>
                        <% end %>
                      </div>
                    </div>

                    <div class="flex flex-wrap gap-2">
                      <%= for group <- @groups do %>
                        <button
                          id={"toggle-user-group-#{user.id}-#{group.id}"}
                          type="button"
                          phx-click={
                            if group.id in user.group_ids,
                              do: "remove_user_group",
                              else: "add_user_group"
                          }
                          phx-value-user_id={user.id}
                          phx-value-group_id={group.id}
                          class={[
                            "rounded-xl border px-3 py-2 text-xs font-semibold transition",
                            group.id in user.group_ids &&
                              "border-emerald-500/30 bg-emerald-500/10 text-emerald-200 hover:bg-emerald-500/20",
                            group.id not in user.group_ids &&
                              "border-slate-700 bg-slate-900 text-slate-300 hover:border-slate-500 hover:bg-slate-800"
                          ]}
                        >
                          <%= if group.id in user.group_ids do %>
                            Remove {group.name}
                          <% else %>
                            Add {group.name}
                          <% end %>
                        </button>
                      <% end %>
                    </div>
                  </div>
                </article>
              <% end %>
            </div>
          </section>

          <section class="rounded-2xl border border-slate-800 bg-slate-900/70 p-5 shadow-xl shadow-slate-950/20">
            <div class="mb-4 flex items-center justify-between">
              <h2 class="text-lg font-semibold text-slate-100">Groups</h2>
            </div>

            <.form for={@group_form} id="admin-group-form" phx-submit="save_group" class="mb-6">
              <div class="grid gap-4 md:grid-cols-[1fr_auto]">
                <label class="space-y-2">
                  <span class="block text-sm font-medium text-slate-300">
                    {if(@editing_group_id, do: "Edit group", else: "Create group")}
                  </span>
                  <input
                    type="text"
                    name={@group_form[:name].name}
                    value={@group_form[:name].value}
                    placeholder="Group name"
                    class="w-full rounded-xl border border-slate-700 bg-slate-950/60 px-4 py-3 text-slate-100 placeholder:text-slate-500 outline-none transition focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20"
                  />
                </label>

                <div class="flex items-end gap-2">
                  <button
                    type="submit"
                    class="rounded-xl bg-indigo-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-indigo-400"
                  >
                    {if @editing_group_id, do: "Update Group", else: "Create Group"}
                  </button>
                  <%= if @editing_group_id do %>
                    <button
                      type="button"
                      phx-click="cancel_group_edit"
                      class="rounded-xl border border-slate-700 px-4 py-2.5 text-sm font-semibold text-slate-300 transition hover:bg-slate-800"
                    >
                      Cancel
                    </button>
                  <% end %>
                </div>
              </div>
            </.form>

            <div class="overflow-hidden rounded-2xl border border-slate-800">
              <table class="min-w-full divide-y divide-slate-800 text-left text-sm">
                <thead class="bg-slate-950/70 text-xs uppercase tracking-[0.2em] text-slate-400">
                  <tr>
                    <th class="px-4 py-3">Group</th>
                    <th class="px-4 py-3">Members</th>
                    <th class="px-4 py-3">Access</th>
                    <th class="px-4 py-3 text-right">Actions</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-slate-800 bg-slate-950/40">
                  <%= for group <- @groups do %>
                    <tr class="align-top">
                      <td class="px-4 py-4">
                        <div class="flex items-center gap-2">
                          <span class="font-medium text-slate-100">{group.name}</span>
                          <%= if group.name == "admin" do %>
                            <span class="rounded-full bg-emerald-500/15 px-2 py-0.5 text-[11px] font-medium text-emerald-300">
                              admin
                            </span>
                          <% end %>
                        </div>
                        <p class="mt-1 text-xs text-slate-500">ID: {group.id}</p>
                      </td>
                      <td class="px-4 py-4 text-slate-300">{group.member_count}</td>
                      <td class="px-4 py-4">
                        <span class="rounded-full bg-slate-800 px-2.5 py-1 text-xs text-slate-300">
                          {if group.name == "admin", do: "Admin", else: "Standard"}
                        </span>
                      </td>
                      <td class="px-4 py-4">
                        <div class="flex justify-end gap-2">
                          <button
                            id={"edit-group-#{group.id}"}
                            type="button"
                            phx-click="edit_group"
                            phx-value-id={group.id}
                            class="rounded-lg border border-slate-700 px-3 py-1.5 text-xs font-semibold text-slate-300 transition hover:bg-slate-800"
                            disabled={group.name == "admin"}
                          >
                            Edit
                          </button>
                          <button
                            id={"delete-group-#{group.id}"}
                            type="button"
                            phx-click="request_delete_group"
                            phx-value-id={group.id}
                            class={[
                              "rounded-lg px-3 py-1.5 text-xs font-semibold transition",
                              group.name == "admin" &&
                                "cursor-not-allowed bg-slate-800 text-slate-500",
                              group.name != "admin" &&
                                "border border-rose-500/30 bg-rose-500/10 text-rose-200 hover:bg-rose-500/20"
                            ]}
                            disabled={group.name == "admin"}
                          >
                            Delete
                          </button>
                        </div>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </section>

          <div class="col-span-full">
            <.live_component
              module={SnowSeToolsWeb.Admin.SnowCacheComponent}
              id="snow-cache-component"
            />
          </div>
        </div>
      </div>
      <:modal :if={@pending_delete}>
        <.modal id="confirm-delete-modal" on_close="cancel_delete">
          <div class="space-y-5">
            <div class="space-y-2">
              <h2 class="text-xl font-semibold text-slate-100">Confirm deletion</h2>
              <p class="text-sm leading-6 text-slate-300">
                Delete {@pending_delete.label}?
              </p>
            </div>

            <div class="flex justify-end gap-3">
              <button
                type="button"
                phx-click="cancel_delete"
                class="rounded-xl border border-slate-700 px-4 py-2.5 text-sm font-semibold text-slate-300 transition hover:bg-slate-800"
              >
                Cancel
              </button>
              <button
                type="button"
                phx-click="confirm_delete"
                class="rounded-xl bg-rose-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-rose-400"
              >
                Delete
              </button>
            </div>
          </div>
        </.modal>
      </:modal>
    </Layouts.app>
    """
  end

  defp groups_for_user(groups, group_ids) do
    MapSet.new(group_ids)
    |> then(fn group_id_set ->
      Enum.filter(groups, fn group -> MapSet.member?(group_id_set, group.id) end)
    end)
  end

  defp reset_group_form(socket) do
    socket
    |> assign(:editing_group_id, nil)
    |> assign(:group_form, to_form(%{"name" => ""}, as: :group))
  end

  defp user_in_admin_group?(groups, group_ids) do
    admin_group_id =
      Enum.find_value(groups, fn group ->
        if group.name == "admin", do: group.id, else: nil
      end)

    admin_group_id in group_ids
  end
end
