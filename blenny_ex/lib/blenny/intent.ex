defmodule Blenny.Intent do
  @moduledoc """
  Defines the intent types for PubSub topic-based routing.

  Intents categorize messages so clients subscribe only to the types of
  content they care about. Each routing intent maps to a PubSub topic:

      blenny:intent:ui            — HTML fragments and signal updates
      blenny:intent:command       — bidirectional request/response traffic
      blenny:intent:notification  — system alerts, toasts, etc.

  `:all` is a meta-intent — clients that declare it subscribe to every
  routing topic.

  The per-user topic `blenny:user:<id>` carries all intents; filtering
  happens at the subscriber based on the intent in the message tuple.
  """

  @type t :: :ui | :command | :notification | :all

  @routing_intents [:ui, :command, :notification]

  @doc """
  Returns the three routing intents (excludes the `:all` meta-intent).
  """
  @spec routing() :: [t()]
  def routing, do: @routing_intents

  @doc """
  Returns all valid intent atoms including `:all`.
  """
  @spec all() :: [t()]
  def all, do: @routing_intents ++ [:all]

  @doc """
  Returns the PubSub topic string for a routing intent.

  Raises on `:all` since it has no single topic.
  """
  @spec to_topic(t()) :: String.t()
  def to_topic(:ui), do: "blenny:intent:ui"
  def to_topic(:command), do: "blenny:intent:command"
  def to_topic(:notification), do: "blenny:intent:notification"

  @doc """
  Returns the per-user PubSub topic. All intents for a user share this topic;
  intent filtering is done by the subscriber.
  """
  @spec user_topic(String.t()) :: String.t()
  def user_topic(user_id) when is_binary(user_id), do: "blenny:user:#{user_id}"

  @doc """
  Parses an intent from a string, returning `{:ok, intent}` or `:error`.
  """
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse(s) when is_binary(s) do
    intent = String.to_existing_atom(s)

    if intent in @routing_intents || intent == :all do
      {:ok, intent}
    else
      :error
    end
  rescue
    ArgumentError -> :error
  end

  @doc """
  Parses a comma-separated list of intent strings.

  Returns `[:all]` when the input is nil or empty (backwards-compatible
  default — no intent declared means receive everything).
  """
  @spec parse_list(String.t() | nil) :: [t()]
  def parse_list(nil), do: [:all]

  def parse_list(s) when is_binary(s) do
    list =
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

    if list == [], do: [:all], else: list
  end

  @doc """
  Returns `true` if the connection's intent list accepts the given message intent.

  `:all` accepts everything. Specific intents match exactly. The `:direct`
  meta-intent (used for user-targeted messages) is always accepted.
  """
  @spec accepts?([t()], t()) :: boolean()
  def accepts?(_intents, :direct), do: true
  def accepts?(intents, intent), do: :all in intents or intent in intents
end
