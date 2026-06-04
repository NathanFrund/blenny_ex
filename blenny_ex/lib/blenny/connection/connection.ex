defmodule Blenny.Connection do
  @moduledoc """
  Represents a single client connection to the Blenny transport system.

  Each connection has a unique `:id` and belongs to a user (or anonymous session).
  The `:conn_type` determines how messages are delivered (`:liveview` via
  Phoenix push_event, or `:sse` via Datastar-formatted events).
  """

  @type conn_type :: :liveview | :sse

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t() | nil,
          conn_type: conn_type(),
          transport_pid: pid() | nil,
          intents: [atom()],
          inserted_at: integer()
        }

  defstruct [
    :id,
    :user_id,
    :conn_type,
    :transport_pid,
    intents: [],
    inserted_at: 0
  ]

  @doc """
  Creates a new `%Blenny.Connection{}` struct.

  The `id` is a unique connection identifier, `conn_type` determines the
  transport (`:liveview` or `:sse`), and `opts` may include `:user_id`,
  `:transport_pid`, and `:intents`. Timestamp (`inserted_at`) is set
  automatically to the current UTC time in milliseconds.

  ## Examples

      Blenny.Connection.new("conn-123", :sse)
      Blenny.Connection.new("conn-456", :liveview, user_id: "user-1")
  """
  @spec new(String.t(), Blenny.Connection.conn_type(), Keyword.t()) :: Blenny.Connection.t()
  def new(id, conn_type, opts \\ []) do
    %__MODULE__{
      id: id,
      user_id: Keyword.get(opts, :user_id),
      conn_type: conn_type,
      transport_pid: Keyword.get(opts, :transport_pid),
      intents: Keyword.get(opts, :intents, []),
      inserted_at: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    }
  end
end
