defmodule SnowSeToolsWeb.Admin.AdminUIMessages do
  def send_users(pid: pid, users: users) when is_pid(pid) do
    send(pid, {:admin_ui_users, users})
  end

  def send_groups(pid: pid, groups: groups) when is_pid(pid) do
    send(pid, {:admin_ui_groups, groups})
  end

  def send_action_result(pid: pid, result: result) when is_pid(pid) do
    send(pid, {:admin_ui_action_result, result})
  end

  defmacro __using__(_opts) do
    quote do
      def handle_info({:admin_ui_users, users}, socket) do
        {:noreply, assign(socket, :users, users)}
      end

      def handle_info({:admin_ui_groups, groups}, socket) do
        {:noreply, assign(socket, :groups, groups)}
      end

      def handle_info({:admin_ui_action_result, {:ok, message}}, socket) do
        {:noreply, assign(socket, :last_action_message, message) |> reset_forms()}
      end

      def handle_info({:admin_ui_action_result, {:error, reason}}, socket) do
        {:noreply, put_flash(socket, :error, format_error(reason))}
      end

      defp reset_forms(socket) do
        socket
        |> assign(:editing_group_id, nil)
        |> assign(:group_form, to_form(%{"name" => ""}, as: :group))
        |> assign(:user_form, to_form(%{"email" => ""}, as: :user))
      end

      defp format_error(reason) when is_binary(reason), do: reason

      defp format_error(:protected_group_locked),
        do: "Built-in access groups cannot be renamed or deleted."

      defp format_error(:last_admin_user),
        do: "You cannot remove the last super user."

      defp format_error(:invalid_group_name), do: "Group name cannot be blank."
      defp format_error(:invalid_email), do: "Email cannot be blank."
      defp format_error(:not_found), do: "That record no longer exists."
      defp format_error(reason), do: inspect(reason)
    end
  end
end
