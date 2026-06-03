defmodule BlennyTestAppWeb.DashboardLive do
  use BlennyTestAppWeb, :live_view
  use Blenny.Transport.LiveViewBridge

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-4xl px-4 py-8">
        <h1 class="text-2xl font-bold mb-2">Blenny Dashboard</h1>
        <p class="text-gray-500 mb-6">
          Live metrics delivered via <strong>LiveView (WebSocket)</strong>.
          <a href="/dashboard-sse" class="text-blue-500 hover:underline ml-2">
            View SSE version
          </a>
        </p>

        <div class="grid grid-cols-3 gap-4 mb-6">
          <div class="rounded-lg border p-4 bg-white shadow-sm">
            <div class="text-sm text-gray-500 mb-1">CPU Usage</div>
            <div class="text-3xl font-bold" id="cpu">{@cpu}%</div>
          </div>
          <div class="rounded-lg border p-4 bg-white shadow-sm">
            <div class="text-sm text-gray-500 mb-1">Memory</div>
            <div class="text-3xl font-bold" id="mem">{@mem} MB</div>
          </div>
          <div class="rounded-lg border p-4 bg-white shadow-sm">
            <div class="text-sm text-gray-500 mb-1">Server Time</div>
            <div class="text-xl font-mono" id="time">{@time}</div>
          </div>
        </div>

        <div class="rounded-lg border p-4 bg-white shadow-sm mb-6">
          <h2 class="text-lg font-semibold mb-3">Broadcast Test</h2>
          <div class="flex gap-2">
            <button
              phx-click="broadcast"
              phx-value-type="html"
              class="rounded bg-blue-500 px-3 py-1.5 text-sm font-medium text-white hover:bg-blue-600"
            >
              Send HTML
            </button>
            <button
              phx-click="broadcast"
              phx-value-type="data"
              class="rounded bg-green-500 px-3 py-1.5 text-sm font-medium text-white hover:bg-green-600"
            >
              Send Data
            </button>
            <button
              phx-click="broadcast"
              phx-value-type="script"
              class="rounded bg-orange-500 px-3 py-1.5 text-sm font-medium text-white hover:bg-orange-600"
            >
              Send Script
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    now = BlennyTestApp.Time.now()

    socket =
      socket
      |> assign(:cpu, 0)
      |> assign(:mem, 0)
      |> assign(:time, now |> Calendar.strftime("%H:%M:%S"))

    {:ok, socket}
  end

  @impl true
  def handle_info({:blenny_msg, _intent, payload}, socket) do
    if signals = payload[:signals] do
      socket =
        socket
        |> assign(:cpu, signals["cpu"] || socket.assigns.cpu)
        |> assign(:mem, signals["mem"] || socket.assigns.mem)
        |> assign(:time, signals["time"] || format_time(signals))

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("broadcast", %{"type" => type}, socket) do
    case type do
      "html" ->
        Blenny.Publisher.broadcast_html(
          ~s|<div class="rounded bg-yellow-100 p-2 my-1 text-sm">Broadcast at #{format_timestamp()}</div>|
        )

      "data" ->
        Blenny.Publisher.broadcast_data(%{
          "cpu" => :rand.uniform(100) - 1,
          "mem" => :rand.uniform(100) - 1,
          "manual" => true
        })

      "script" ->
        Blenny.Publisher.execute_script(
          "console.log('Blenny broadcast at #{format_timestamp()}')"
        )
    end

    {:noreply, socket}
  end

  defp format_time(%{"timestamp" => ts}) when is_integer(ts) do
    BlennyTestApp.Time.from_unix_ms(ts)
  end

  defp format_time(_), do: BlennyTestApp.Time.format_timestamp()

  defp format_timestamp do
    BlennyTestApp.Time.format_timestamp()
  end
end
