defmodule Blenny.Transport.LiveViewBridge do
  @moduledoc """
  Integrates a Phoenix LiveView with the Blenny transport system.

  When a LiveView calls `use Blenny.Transport.LiveViewBridge`, it automatically
  registers with the `Blenny.Hub` on mount and cleans up on unmount.

  The LiveView should implement `handle_info({:blenny_message, conn_id, msg}, socket)`
  to receive real-time messages and forward them to the client via `push_event/3`.

  ## Usage

      defmodule MyAppWeb.DashboardLive do
        use MyAppWeb, :live_view
        use Blenny.Transport.LiveViewBridge, intents: [:ui, :data]

        @impl true
        def handle_info({:blenny_message, _conn_id, msg}, socket) do
          socket = if msg[:signals] do
            assign(socket, cpu: msg[:signals]["cpu"], mem: msg[:signals]["mem"])
          else
            socket
          end
          {:noreply, socket}
        end
      end
  """

  defmacro __using__(opts) do
    quote do
      on_mount {Blenny.Transport.LiveViewBridge, unquote(opts)}
    end
  end

  @doc false
  def on_mount(:not_mounted_at_router, _params, _session, socket) do
    {:cont, socket}
  end

  @doc false
  def on_mount(opts, _params, _session, socket) when is_list(opts) do
    session_id =
      socket.assigns[:blenny_session_id] ||
        :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

    user_id =
      case socket.assigns[:current_user] do
        %{id: id} when not is_nil(id) -> to_string(id)
        _ -> nil
      end

    conn_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

    conn =
      Blenny.Connection.new(conn_id, session_id, :liveview,
        transport_pid: self(),
        user_id: user_id
      )

    {:ok, _} = Blenny.Hub.register_connection(conn)
    {:cont, Phoenix.Component.assign(socket, :blenny_conn_id, conn_id)}
  end
end
