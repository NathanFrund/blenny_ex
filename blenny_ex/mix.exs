defmodule BlennyEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :blenny_ex,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:bandit, "~> 1.5", optional: true},
      {:jason, "~> 1.2"},
      {:telemetry, "~> 1.0"},
      {:nimble_options, "~> 1.0"}
    ]
  end
end
