defmodule BlennyTestApp.Blenny.DashboardModule do
  @moduledoc """
  Demonstates a Blenny module that provides dashboard routes and
  publishes periodic metrics via `Blenny.Publisher`.
  """

  use Blenny.Module

  require Logger

  @impl true
  def name, do: "dashboard"

  @impl true
  def routes do
    [
      %{method: :get, path: "/dashboard", handler: BlennyTestAppWeb.DashboardLive, auth: false},
      %{
        method: :get,
        path: "/dashboard-sse",
        handler: BlennyTestAppWeb.SSEDashboardController,
        auth: false
      }
    ]
  end

  @impl true
  def capabilities, do: []

  @impl true
  def subscriptions, do: []

  @impl true
  def initialize(_state) do
    Logger.info("[Blenny] Dashboard module initialized")
    :ok
  end

  @impl true
  def start do
    spawn(fn -> metrics_loop() end)
    :ok
  end

  @impl true
  def stop do
    :ok
  end

  defp metrics_loop do
    {run_now, _} = :erlang.statistics(:runtime)
    {wc_now, _} = :erlang.statistics(:wall_clock)

    Process.sleep(2_000)

    {run_after, _} = :erlang.statistics(:runtime)
    {wc_after, _} = :erlang.statistics(:wall_clock)

    now = DateTime.utc_now()

    metrics = %{
      "cpu" => cpu_pct({run_now, wc_now}, {run_after, wc_after}),
      "mem" => mem_mb(),
      "time" => now |> Calendar.strftime("%H:%M:%S"),
      "timestamp" => now |> DateTime.to_unix(:millisecond)
    }

    Blenny.Publisher.broadcast_data(metrics)
    metrics_loop()
  end

  defp cpu_pct({run_before, wc_before}, {run_after, wc_after}) do
    run_diff = run_after - run_before
    wc_diff = wc_after - wc_before

    if wc_diff > 0 do
      (run_diff / wc_diff * 100) |> Float.round(1)
    else
      0.0
    end
  end

  defp mem_mb do
    (:erlang.memory(:total) / 1_048_576)
    |> Float.round(1)
  end
end
