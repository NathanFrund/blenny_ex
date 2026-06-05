defmodule SurrealDB.MixProject do
  use Mix.Project

  def project do
    [
      app: :surrealdb,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      description: "Lightweight SurrealDB client for Elixir — WebSocket, live queries, telemetry",
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {SurrealDB.Application, []}
    ]
  end

  defp deps do
    [
      {:websockex, "~> 0.4"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:nimble_options, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
