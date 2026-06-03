defmodule Blenny.Transport.LiveViewBridge do
  @moduledoc """
  Integrates a Phoenix LiveView with the Blenny transport system.

  When a LiveView calls `use Blenny.Transport.LiveViewBridge`, it automatically
  registers with the `Blenny.Hub` on mount, subscribes to PubSub topics, and
  cleans up on unmount.

  The LiveView receives `{:blenny_msg, intent, payload}` messages directly
  from PubSub (its `handle_info/2` clause should match that tuple).

  ## Usage

      defmodule MyAppWeb.DashboardLive do
        use MyAppWeb, :live_view
        use Blenny.Transport.LiveViewBridge, intents: [:ui]

        @impl true
        def handle_info({:blenny_msg, _intent, payload}, socket) do
          socket = if payload[:signals] do
            assign(socket, cpu: payload[:signals]["cpu"], mem: payload[:signals]["mem"])
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
    intents = Keyword.get(opts, :intents, [:all])

    user_id =
      case socket.assigns[:current_user] do
        %{id: id} when not is_nil(id) -> to_string(id)
        _ -> nil
      end

    conn_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

    conn =
      Blenny.Connection.new(conn_id, :liveview,
        transport_pid: self(),
        user_id: user_id,
        intents: intents
      )

    :ok = Blenny.Hub.register_connection(conn)

    pubsub = Blenny.pub_sub()
    for intent <- Blenny.Intent.routing() do
      Phoenix.PubSub.subscribe(pubsub, Blenny.Intent.to_topic(intent), link: true)
    end

    user_topic = Blenny.Intent.user_topic(user_id || conn_id)
    Phoenix.PubSub.subscribe(pubsub, user_topic, link: true)

    {:cont, Phoenix.Component.assign(socket, :blenny_conn_id, conn_id)}
  end
end
