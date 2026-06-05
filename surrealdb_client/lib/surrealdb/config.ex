defmodule SurrealDB.Config do
  @schema [
    hostname: [
      type: :string,
      default: "localhost",
      doc: "SurrealDB server hostname"
    ],
    port: [
      type: :integer,
      default: 8000,
      doc: "SurrealDB WebSocket port"
    ],
    tls: [
      type: :boolean,
      default: false,
      doc: "Use wss:// instead of ws://"
    ],
    namespace: [
      type: :string,
      default: "test",
      doc: "SurrealDB namespace"
    ],
    database: [
      type: :string,
      default: "test",
      doc: "SurrealDB database"
    ],
    username: [
      type: :string,
      default: "root",
      doc: "SurrealDB username"
    ],
    password: [
      type: :string,
      default: "root",
      doc: "SurrealDB password"
    ],
    name: [
      type: {:or, [:atom, {:in, [nil]}]},
      default: nil,
      doc: "Optional registered name for the connection process"
    ],
    backoff_max: [
      type: :pos_integer,
      default: 10_000,
      doc: "Maximum reconnection backoff in milliseconds"
    ],
    backoff_step: [
      type: :pos_integer,
      default: 50,
      doc: "Reconnection backoff increment per attempt in milliseconds"
    ],
    query_timeout: [
      type: :pos_integer,
      default: 5_000,
      doc: "Default timeout for queries in milliseconds"
    ],
    on_auth: [
      type: {:or, [{:fun, 2}, {:in, [nil]}]},
      default: nil,
      doc: "Optional callback (pid, state) called after connect for custom auth flow"
    ]
  ]

  @doc "Returns the NimbleOptions schema for validation."
  def schema, do: @schema

  @doc "Validates the given options against the schema."
  def validate!(opts) do
    NimbleOptions.validate!(opts, @schema)
  end

  @doc "Merges provided opts with defaults and validates."
  def compile(opts) do
    NimbleOptions.validate!(opts, @schema)
    elem(NimbleOptions.validate(opts, @schema), 1)
  end
end
