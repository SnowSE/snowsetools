defmodule SnowSeToolsWeb.Admin.AdminLive do
  use SnowSeToolsWeb, :live_view
  use SnowSeToolsWeb.Admin.AdminUIMessages
  use SnowSeToolsWeb.Admin.AdminSnowCoursesUIMessages

  alias SnowSeTools.Data.Access
  alias SnowSeTools.Snow.SnowCourseCacheDomainManager
  alias SnowSeTools.UserGroups.UserGroupDomainManager
  alias SnowSeToolsWeb.UserAuth

  on_mount {UserAuth, {:ensure_access, :admin}}

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

            <p class="mb-4 text-xs leading-5 text-slate-500">
              New accounts start with no access and see an "awaiting approval" page.
              Toggle the areas each person may use; <span class="text-emerald-300">Super user</span>
              grants everything, including this page.
            </p>

            <div class="space-y-3">
              <%= for user <- sorted_users(@users) do %>
                <article
                  id={"admin-user-#{user.id}"}
                  class={[
                    "rounded-2xl border p-4",
                    pending?(user) && "border-amber-500/40 bg-amber-500/5",
                    !pending?(user) && "border-slate-800 bg-slate-950/50"
                  ]}
                >
                  <div class="flex flex-wrap items-center gap-2">
                    <h3 class="font-medium text-slate-100">{user.email}</h3>
                    <%= if pending?(user) do %>
                      <span class="rounded-full bg-amber-500/15 px-2 py-0.5 text-[11px] font-medium text-amber-300">
                        awaiting approval
                      </span>
                    <% end %>
                    <%= if Access.admin?(user) do %>
                      <span class="rounded-full bg-emerald-500/15 px-2 py-0.5 text-[11px] font-medium text-emerald-300">
                        super user
                      </span>
                    <% end %>
                    <%= if user.id == @current_user.id do %>
                      <span class="rounded-full bg-slate-800 px-2 py-0.5 text-[11px] font-medium text-slate-400">
                        you
                      </span>
                    <% end %>
                  </div>

                  <div class="mt-3 flex flex-wrap gap-2">
                    <%= for area <- Access.areas(), group = group_named(@groups, area.group), group do %>
                      <.group_toggle
                        user={user}
                        group={group}
                        label={area.label}
                        title={area.description}
                        admin_area?={area.area == :admin}
                      />
                    <% end %>
                    <%= for group <- custom_groups(@groups) do %>
                      <.group_toggle
                        user={user}
                        group={group}
                        label={group.name}
                        title="Custom group"
                      />
                    <% end %>
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
                    <th class="px-4 py-3">Grants</th>
                    <th class="px-4 py-3">Members</th>
                    <th class="px-4 py-3 text-right">Actions</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-slate-800 bg-slate-950/40">
                  <%= for group <- @groups, protected? = Access.protected_group?(group.name) do %>
                    <tr class="align-top">
                      <td class="px-4 py-4">
                        <div class="flex items-center gap-2">
                          <span class="font-medium text-slate-100">{group.name}</span>
                          <%= if protected? do %>
                            <span class="rounded-full bg-slate-800 px-2 py-0.5 text-[11px] font-medium text-slate-400">
                              built-in
                            </span>
                          <% end %>
                        </div>
                      </td>
                      <td class="px-4 py-4 text-slate-300">
                        <%= case Access.area_for_group(group.name) do %>
                          <% %{label: label, description: description} -> %>
                            <span class="font-medium text-slate-200">{label}</span>
                            <p class="mt-1 text-xs leading-5 text-slate-500">{description}</p>
                          <% nil -> %>
                            <span class="text-xs text-slate-500">Custom group — grants no built-in access</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-4 text-slate-300">{group.member_count}</td>
                      <td class="px-4 py-4">
                        <div class="flex justify-end gap-2">
                          <button
                            id={"edit-group-#{group.id}"}
                            type="button"
                            phx-click="edit_group"
                            phx-value-id={group.id}
                            class="rounded-lg border border-slate-700 px-3 py-1.5 text-xs font-semibold text-slate-300 transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-40"
                            disabled={protected?}
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
                              protected? && "cursor-not-allowed bg-slate-800 text-slate-500",
                              !protected? &&
                                "border border-rose-500/30 bg-rose-500/10 text-rose-200 hover:bg-rose-500/20"
                            ]}
                            disabled={protected?}
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

  attr :user, :map, required: true
  attr :group, :map, required: true
  attr :label, :string, required: true
  attr :title, :string, default: nil
  attr :admin_area?, :boolean, default: false

  defp group_toggle(assigns) do
    assigns = assign(assigns, :member?, assigns.group.id in assigns.user.group_ids)

    ~H"""
    <button
      id={"toggle-user-group-#{@user.id}-#{@group.id}"}
      type="button"
      title={@title}
      phx-click={if @member?, do: "remove_user_group", else: "add_user_group"}
      phx-value-user_id={@user.id}
      phx-value-group_id={@group.id}
      class={[
        "inline-flex items-center gap-1.5 rounded-xl border px-3 py-1.5 text-xs font-semibold transition",
        @member? && @admin_area? &&
          "border-emerald-500/40 bg-emerald-500/15 text-emerald-200 hover:bg-emerald-500/25",
        @member? && !@admin_area? &&
          "border-indigo-500/40 bg-indigo-500/15 text-indigo-200 hover:bg-indigo-500/25",
        !@member? &&
          "border-slate-700 bg-slate-900 text-slate-400 hover:border-slate-500 hover:text-slate-200"
      ]}
    >
      <.icon name={if @member?, do: "hero-check-circle", else: "hero-plus-circle"} class="size-4" />
      {@label}
    </button>
    """
  end

  defp pending?(user), do: !Access.approved?(user)

  # Accounts waiting for approval first, then by sign-up order.
  defp sorted_users(users), do: Enum.sort_by(users, &{!pending?(&1), &1.inserted_at})

  defp group_named(groups, name), do: Enum.find(groups, &(&1.name == name))

  defp custom_groups(groups), do: Enum.reject(groups, &Access.protected_group?(&1.name))

  defp reset_group_form(socket) do
    socket
    |> assign(:editing_group_id, nil)
    |> assign(:group_form, to_form(%{"name" => ""}, as: :group))
  end
end
