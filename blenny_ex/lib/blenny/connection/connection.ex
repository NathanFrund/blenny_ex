defmodule Blenny.Connection do
  @moduledoc """
  Represents a single client connection to the Blenny transport system.

  Each connection is identified by a unique `:id` and belongs to a session and
  optionally a user. The `:conn_type` determines how messages are delivered to
  this client (`:liveview` via push_event, or `:sse` via Datastar-formatted events).
  """

  @type conn_type :: :liveview | :sse

  @type t :: %__MODULE__{
          id: String.t(),
          session_id: String.t(),
          user_id: String.t() | nil,
          conn_type: conn_type(),
          transport_pid: pid() | nil,
          subscribed_topics: [String.t()],
          inserted_at: integer()
        }

  defstruct [
    :id,
    :session_id,
    :user_id,
    :conn_type,
    :transport_pid,
    subscribed_topics: [],
    inserted_at: 0
  ]

  @doc false
  def new(id, session_id, conn_type, opts \\ []) do
    %__MODULE__{
      id: id,
      session_id: session_id,
      user_id: Keyword.get(opts, :user_id),
      conn_type: conn_type,
      transport_pid: Keyword.get(opts, :transport_pid),
      inserted_at: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    }
  end
end
