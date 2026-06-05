defmodule BlennyEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :blenny_ex,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Multi-transport hypermedia engine for Phoenix — SSE (Datastar) and LiveView",
      source_url: "https://github.com/NathanFrund/blenny_ex",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/NathanFrund/blenny_ex"},
        maintainers: ["Nathan Frund"]
      ],
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def docs do
    [
      main: "readme",
      extras: ["guides/realtime_notifications.md"]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:bandit, "~> 1.5", optional: true},
      {:jason, "~> 1.2"},
      {:telemetry, "~> 1.0"},
      {:nimble_options, "~> 1.0"},
      {:dstar, "~> 0.0.10"},
      {:surrealdb, "~> 0.1", path: "../surrealdb_client"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
