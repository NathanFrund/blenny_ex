defmodule BlennyEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :blenny_ex,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      description: "Multi-transport hypermedia engine for Phoenix — SSE (Datastar) and LiveView",
      source_url: "https://github.com/anomalyco/blenny_ex",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/anomalyco/blenny_ex"},
        maintainers: []
      ],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
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
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
