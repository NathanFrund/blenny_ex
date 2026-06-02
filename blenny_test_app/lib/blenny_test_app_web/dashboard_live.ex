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

        <div class="rounded-lg border p-4 bg-white shadow-sm">
          <h2 class="text-lg font-semibold mb-2">Event Log</h2>
          <div
            id="event-log"
            phx-update="stream"
            class="h-40 overflow-y-auto rounded bg-gray-50 p-3 font-mono text-sm"
          >
            <div :for={{id, entry} <- @streams.events} id={id} class="border-b border-gray-100 py-1">
              <span class="text-gray-400">{entry.timestamp}</span>
              {" "}
              <span class={
                (entry.type == "signal" && "text-green-600") ||
                  (entry.type == "html" && "text-blue-600") || "text-orange-600"
              }>
                {entry.text}
              </span>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:cpu, 0)
      |> assign(:mem, 0)
      |> assign(:time, DateTime.utc_now() |> Calendar.strftime("%H:%M:%S"))
      |> stream(:events, [])

    {:ok, socket}
  end

  @impl true
  def handle_info({:blenny_message, _conn_id, msg}, socket) do
    socket =
      if msg[:signals] do
        entry = %{
          id: unique_id(),
          type: "signal",
          text: "signals: #{inspect(msg[:signals])}",
          timestamp: format_timestamp()
        }

        socket
        |> assign(:cpu, msg[:signals]["cpu"] || socket.assigns.cpu)
        |> assign(:mem, msg[:signals]["mem"] || socket.assigns.mem)
        |> assign(:time, format_time(msg[:signals]))
        |> stream(:events, [entry], at: -1)
      else
        socket
      end

    {:noreply, socket}
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
          cpu: :rand.uniform(100) - 1,
          mem: :rand.uniform(100) - 1,
          manual: true
        })

      "script" ->
        Blenny.Publisher.execute_script(
          "console.log('Blenny broadcast at #{format_timestamp()}')"
        )
    end

    {:noreply, socket}
  end

  defp format_time(%{"timestamp" => ts}) when is_integer(ts) do
    DateTime.from_unix!(div(ts, 1000)) |> Calendar.strftime("%H:%M:%S")
  end

  defp format_time(_), do: DateTime.utc_now() |> Calendar.strftime("%H:%M:%S")

  defp format_timestamp do
    DateTime.utc_now() |> Calendar.strftime("%H:%M:%S")
  end

  defp unique_id do
    {mega, sec, micro} = :os.timestamp()
    "#{mega}-#{sec}-#{micro}"
  end
end
