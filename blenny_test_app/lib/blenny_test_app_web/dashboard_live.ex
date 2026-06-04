defmodule BlennyTestAppWeb.DashboardLive do
  use BlennyTestAppWeb, :live_view
  use Blenny.Transport.LiveViewBridge

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-4xl px-4 py-8">
        <h1 class="text-2xl font-bold mb-2">Blenny Dashboard</h1>

        <div
          :if={@display_name}
          class="mb-4 flex items-center gap-2 rounded-lg border bg-green-50 p-3 text-sm"
        >
          <span class="text-green-700">Signed in as <strong>{@display_name}</strong></span>
          <.link
            href="/auth/signout"
            method="post"
            class="ml-auto text-sm text-gray-500 hover:text-gray-700 underline"
          >
            Sign out
          </.link>
        </div>

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
          <h2 class="text-lg font-semibold mb-3">Event Log</h2>
          <div id="event-log" class="space-y-1 max-h-64 overflow-y-auto text-sm font-mono">
            <div :for={event <- @events} class="flex gap-2">
              <span class="text-gray-400 shrink-0">{event.time}</span>
              <span>{event.message}</span>
            </div>
            <div :if={@events == []} class="text-gray-400 italic">
              No events yet
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    now = BlennyTestApp.Time.now()
    display_name = session["blenny_user_display_name"]

    socket =
      socket
      |> assign(:cpu, 0)
      |> assign(:mem, 0)
      |> assign(:time, now |> Calendar.strftime("%H:%M:%S"))
      |> assign(:events, [])
      |> assign(:display_name, display_name)

    {:ok, socket}
  end

  @impl true
  def handle_info({:blenny_msg, intent, payload}, socket) do
    socket =
      if signals = payload[:signals] do
        time = signals["time"] || format_time(signals)
        cpu = signals["cpu"]
        mem = signals["mem"]

        event = %{
          time: time,
          message: format_event_message(intent, cpu, mem)
        }

        events = [event | socket.assigns.events] |> Enum.take(20)

        socket
        |> assign(:cpu, cpu || socket.assigns.cpu)
        |> assign(:mem, mem || socket.assigns.mem)
        |> assign(:time, time)
        |> assign(:events, events)
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

  defp format_event_message(_intent, cpu, _mem) when not is_nil(cpu) do
    "CPU #{cpu}%"
  end

  defp format_event_message(_intent, nil, mem) when not is_nil(mem) do
    "Memory #{mem} MB"
  end

  defp format_event_message(_intent, nil, nil) do
    "Signal update"
  end
end
