defmodule BlennyExampleApp.Blenny.DashboardModule do
  @moduledoc """
  A stateful Blenny module that provides dashboard routes and publishes
  periodic VM metrics via `Blenny.Publisher`.

  Runs as a supervised GenServer under `Blenny.ModuleSupervisor`. The metrics
  loop uses `Process.send_after/3` — no raw `spawn`, fully OTP-native.
  """

  use Blenny.Module
  use GenServer

  require Logger

  @tick_ms 2_000

  # ── Blenny.Module callbacks ───────────────────────────────────

  @impl true
  def name, do: "dashboard"

  @blenny_routes {:live, "/dashboard", BlennyExampleAppWeb.DashboardLive}
  @blenny_routes {:http, :get, "/dashboard-sse", BlennyExampleAppWeb.SSEDashboardController,
                  :index}

  @impl true
  def routes, do: @blenny_routes

  @impl true
  def capabilities, do: []

  @impl true
  def subscriptions, do: []

  @impl true
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      restart: :permanent,
      type: :worker
    }
  end

  @impl true
  def initialize(_state) do
    Logger.info("[Blenny] Dashboard module initialized")
    :ok
  end

  # ── GenServer callbacks ───────────────────────────────────────

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {Blenny.ModuleRegistry, {:global, __MODULE__}}}
    )
  end

  @impl true
  def init(_opts) do
    Logger.info("[Blenny] Dashboard metrics loop started")
    schedule_tick()
    {:ok, %{run_before: nil, wc_before: nil}}
  end

  @impl true
  def handle_info(:tick, state) do
    {run_now, _} = :erlang.statistics(:runtime)
    {wc_now, _} = :erlang.statistics(:wall_clock)

    metrics = gather_metrics(state, {run_now, wc_now})
    Blenny.Publisher.broadcast_data(metrics)

    schedule_tick()
    {:noreply, %{state | run_before: run_now, wc_before: wc_now}}
  end

  # ── Private helpers ───────────────────────────────────────────

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end

  defp gather_metrics(%{run_before: nil}, _current), do: zero_metrics()

  defp gather_metrics(%{run_before: rb, wc_before: wb}, {rn, wn}) do
    now = BlennyExampleApp.Time.now()
    now_utc = DateTime.utc_now()

    %{
      "cpu" => cpu_pct({rb, wb}, {rn, wn}),
      "mem" => mem_mb(),
      "time" => now |> Calendar.strftime("%H:%M:%S"),
      "timestamp" => now_utc |> DateTime.to_unix(:millisecond)
    }
  end

  defp zero_metrics do
    now = BlennyExampleApp.Time.now()
    now_utc = DateTime.utc_now()

    %{
      "cpu" => 0.0,
      "mem" => mem_mb(),
      "time" => now |> Calendar.strftime("%H:%M:%S"),
      "timestamp" => now_utc |> DateTime.to_unix(:millisecond)
    }
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
