defmodule Blenny.Publisher do
  @moduledoc """
  Zero-ceremony API for broadcasting messages to Blenny-connected clients.

  All functions publish to `Phoenix.PubSub` topics (`blenny:intent:*`,
  `blenny:user:*`). Transport processes subscribe to these topics and
  receive the messages directly in their mailbox.

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
  """
  @spec broadcast_html(String.t()) :: :ok
  def broadcast_html(html) when is_binary(html) do
    publish("blenny:intent:ui", {:blenny_msg, :ui, %{html: html}})
  end

  @doc """
  Sends an HTML fragment to a specific user's connections.
  """
  @spec direct_html(String.t(), String.t()) :: :ok
  def direct_html(html, user_id) when is_binary(html) and is_binary(user_id) do
    publish("blenny:user:#{user_id}", {:blenny_msg, :direct, %{html: html}})
  end

  @doc """
  Broadcasts signal data (JSON) to all connections.

  Data is published under the `:ui` intent and delivered alongside HTML updates.
  """
  @spec broadcast_data(map() | String.t()) :: :ok
  def broadcast_data(data)

  def broadcast_data(data) when is_map(data) do
    publish("blenny:intent:ui", {:blenny_msg, :ui, %{signals: data}})
  end

  def broadcast_data(data) when is_binary(data) do
    data |> Jason.decode!() |> broadcast_data()
  end

  @doc """
  Sends signal data to a specific user.
  """
  @spec direct_data(map() | String.t(), String.t()) :: :ok
  def direct_data(data, user_id) do
    data_map = if is_binary(data), do: Jason.decode!(data), else: data
    publish("blenny:user:#{user_id}", {:blenny_msg, :direct, %{signals: data_map}})
  end

  @doc """
  Broadcasts a JavaScript snippet to all connections subscribed to the `:command` intent.
  """
  @spec execute_script(String.t()) :: :ok
  def execute_script(script) when is_binary(script) do
    publish("blenny:intent:command", {:blenny_msg, :command, %{script: script}})
  end

  defp publish(topic, msg) do
    Phoenix.PubSub.broadcast(Blenny.pub_sub(), topic, msg)
    :ok
  end
end
