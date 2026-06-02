defmodule Blenny.Intent do
  @moduledoc """
  Defines the intent types for PubSub topic-based routing.

  Intents are used to categorize messages so clients can subscribe only to
  the types of content they care about. Each intent maps to a PubSub topic
  prefix: `"blenny:intent:<intent>"`.

  The standard intents mirror the Blenny-ts design:

    - `:ui`           — HTML fragment patches for DOM updates
    - `:data`         — Signal/state data merges (JSON)
    - `:command`      — Script execution on the client
    - `:notification` — User-facing notifications
    - `:clock`        — Periodic time/tick signals
  """

  @type t :: :ui | :data | :command | :notification | :clock

  @doc """
  Returns all valid intent atoms.
  """
  @spec all() :: [t()]
  def all, do: [:ui, :data, :command, :notification, :clock]

  @doc """
  Returns the PubSub topic string for a given intent.
  """
  @spec to_topic(t()) :: String.t()
  def to_topic(:ui), do: "blenny:intent:ui"
  def to_topic(:data), do: "blenny:intent:data"
  def to_topic(:command), do: "blenny:intent:command"
  def to_topic(:notification), do: "blenny:intent:notification"
  def to_topic(:clock), do: "blenny:intent:clock"

  @doc """
  Returns the per-user PubSub topic string for a given intent and user ID.
  """
  @spec to_user_topic(t(), String.t()) :: String.t()
  def to_user_topic(:ui, user_id), do: "blenny:user:#{user_id}:ui"
  def to_user_topic(:data, user_id), do: "blenny:user:#{user_id}:data"
  def to_user_topic(:command, user_id), do: "blenny:user:#{user_id}:command"
  def to_user_topic(:notification, user_id), do: "blenny:user:#{user_id}:notification"
  def to_user_topic(:clock, user_id), do: "blenny:user:#{user_id}:clock"

  @doc """
  Parses an intent from a string, returning `{:ok, intent}` or `:error`.
  """
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse(s) when is_binary(s) do
    intent = String.to_existing_atom(s)
    if intent in [:ui, :data, :command, :notification, :clock] do
      {:ok, intent}
    else
      :error
    end
  rescue
    ArgumentError -> :error
  end

  @doc """
  Parses a comma-separated list of intent strings.
  """
  @spec parse_list(String.t() | nil) :: [t()]
  def parse_list(nil), do: []

  def parse_list(s) when is_binary(s) do
    s
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reduce([], fn part, acc ->
      case parse(part) do
        {:ok, intent} -> [intent | acc]
        :error -> acc
      end
    end)
    |> Enum.reverse()
  end
end
