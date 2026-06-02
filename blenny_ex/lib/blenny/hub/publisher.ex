defmodule Blenny.Publisher do
  @moduledoc """
  Zero-ceremony API for broadcasting messages to Blenny-connected clients.

  All functions delegate to `Phoenix.PubSub.broadcast/3`, which the
  `Blenny.Hub` subscribes to and dispatches to the appropriate transport
  processes (LiveView or SSE).

  ## Examples

      Blenny.Publisher.broadcast_html(~s|<div id="status">Done</div>|)

      Blenny.Publisher.direct_html(
        ~s|<div id="notice">Your report is ready</div>|,
        user_id
      )

      Blenny.Publisher.broadcast_data(~s|{"cpu": 45, "mem": 62}|)

      Blenny.Publisher.direct_data(~s|{"score": 42}|, user_id)

      Blenny.Publisher.execute_script("console.log('hi')")
  """

  @doc """
  Broadcasts an HTML fragment to all connections subscribed to the `:ui` intent.

  The HTML is sent verbatim. For user-generated content, ensure proper escaping.
  """
  @spec broadcast_html(String.t(), keyword()) :: :ok
  def broadcast_html(html, opts \\ []) when is_binary(html) do
    msg = build_msg(:ui, html, opts)
    broadcast("blenny:intent:ui", msg)
  end

  @doc """
  Sends an HTML fragment to a specific user's connections.

  Matches any connection with the given `:user_id`, regardless of intent.
  """
  @spec direct_html(String.t(), String.t(), keyword()) :: :ok
  def direct_html(html, user_id, opts \\ []) when is_binary(html) and is_binary(user_id) do
    msg = build_msg(:direct, html, opts) |> Map.put(:user_id, user_id)
    broadcast("blenny:direct", msg)
  end

  @doc """
  Broadcasts signal data (JSON) to all connections subscribed to the `:data` intent.
  """
  @spec broadcast_data(map() | String.t(), keyword()) :: :ok
  def broadcast_data(data, opts \\ [])

  def broadcast_data(data, opts) when is_map(data) do
    msg = build_msg(:data, nil, opts) |> Map.put(:signals, data)
    broadcast("blenny:intent:data", msg)
  end

  def broadcast_data(data, opts) when is_binary(data) do
    data
    |> Jason.decode!()
    |> broadcast_data(opts)
  end

  @doc """
  Sends signal data to a specific user.
  """
  @spec direct_data(map() | String.t(), String.t(), keyword()) :: :ok
  def direct_data(data, user_id, opts \\ []) do
    data_map = if is_binary(data), do: Jason.decode!(data), else: data
    msg = build_msg(:direct, nil, opts) |> Map.put(:signals, data_map) |> Map.put(:user_id, user_id)
    broadcast("blenny:direct", msg)
  end

  @doc """
  Broadcasts a JavaScript snippet to all connections subscribed to the `:command` intent.

  Script is sent verbatim. Only use with trusted content.
  """
  @spec execute_script(String.t(), keyword()) :: :ok
  def execute_script(script, opts \\ []) when is_binary(script) do
    msg = build_msg(:command, nil, opts) |> Map.put(:script, script)
    broadcast("blenny:intent:command", msg)
  end

  @doc """
  Broadcasts a raw message to an arbitrary PubSub topic.

  The message should be a map. The Hub dispatches it to matching connections.
  """
  @spec broadcast(String.t(), map()) :: :ok
  def broadcast(topic, msg) when is_binary(topic) and is_map(msg) do
    Phoenix.PubSub.broadcast(Blenny.pub_sub(), topic, msg)
    :ok
  end

  defp build_msg(:direct, html, _opts), do: %{html: html}
  defp build_msg(_intent, nil, _opts), do: %{}
  defp build_msg(_intent, html, _opts), do: %{html: html}
end
