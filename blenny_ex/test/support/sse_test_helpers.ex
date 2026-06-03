defmodule Blenny.Test.SSEHelpers do
  @moduledoc false

  @doc """
  Starts Phoenix.PubSub.PG2 with the given name.
  """
  def start_pubsub(name) do
    {:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: name)
    name
  end

  @doc """
  Starts the Hub GenServer with the default name `Blenny.Hub`.
  """
  def start_hub do
    {:ok, _} = Blenny.Hub.start_link(name: Blenny.Hub)
    :ok
  end

  @doc """
  Starts Bandit with the given endpoint plug on a random port.
  Returns `{pid, port}`.
  """
  def start_bandit(endpoint) do
    {:ok, pid} =
      Bandit.start_link(
        plug: endpoint,
        port: 0,
        thousand_island_options: [shutdown_timeout: 100]
      )

    {:ok, info} = ThousandIsland.listener_info(pid)
    {pid, info.port}
  end

  @doc """
  Connects to Bandit via TCP and sends an HTTP GET request.
  Returns `{socket, headers}`.
  """
  def connect_and_request(port, path \\ "/sse?intent=all") do
    {:ok, socket} =
      :gen_tcp.connect(~c"localhost", port, [:binary, active: false], :timer.seconds(3))

    :ok = :gen_tcp.send(socket, "GET #{path} HTTP/1.1\r\nHost: localhost\r\nAccept: */*\r\n\r\n")
    {socket, read_headers(socket, "", 2000)}
  end

  @doc """
  Reads all available data from the TCP socket with a timeout.
  Returns a binary.
  """
  def read_raw(socket, timeout \\ 1000) do
    read_loop(socket, "", timeout)
  end

  @doc """
  Publishes a Blenny message via PubSub and returns the accumulated
  raw data after the publish.
  """
  def publish_and_read(pubsub, intent, payload, socket, timeout \\ 500) do
    Phoenix.PubSub.broadcast(
      pubsub,
      Blenny.Intent.to_topic(intent),
      {:blenny_msg, intent, payload}
    )

    :timer.sleep(50)
    read_raw(socket, timeout)
  end

  @doc """
  Extracts SSE events from raw chunked HTTP response data.
  Returns a list of event strings, each containing event:/data:/: lines.
  """
  def extract_events(raw) do
    # Strip HTTP headers
    body =
      case String.split(raw, "\r\n\r\n", parts: 2) do
        [_, b] -> b
        [d] -> d
      end

    # Extract SSE events by splitting on \n\n
    # The chunked encoding boundaries (\r\n<hex>\r\n) are in between and get
    # filtered out because they don't contain event:/data:/: prefixes
    events = String.split(body, "\n\n")

    events
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 in ["", "\r"]))
    |> Enum.reject(&match?({_, ""}, Integer.parse(&1, 16)))
    |> Enum.filter(fn ev ->
      String.contains?(ev, "event:") or String.contains?(ev, "\ndata:") or
        String.starts_with?(ev, "data:") or String.starts_with?(ev, ": ")
    end)
  end

  @doc """
  Parses an SSE event string into its event type, data lines, and raw form.
  """
  def parse_event(event_str) do
    lines = String.split(event_str, "\n")

    event_type =
      lines
      |> Enum.find_value("", fn l ->
        case l do
          "event: " <> rest -> rest
          _ -> nil
        end
      end)

    data_lines =
      lines
      |> Enum.filter(&String.starts_with?(&1, "data: "))
      |> Enum.map(&String.trim_leading(&1, "data: "))

    %{event: event_type, data: data_lines, raw: event_str}
  end

  # ── Private ──────────────────────────────────────────────────────

  defp read_headers(socket, acc, timeout) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, data} ->
        new_acc = acc <> data

        case String.split(new_acc, "\r\n\r\n", parts: 2) do
          [_, _rest] -> new_acc
          _ -> read_headers(socket, new_acc, timeout)
        end

      {:error, _reason} ->
        acc
    end
  end

  defp read_loop(_socket, acc, 0), do: acc

  defp read_loop(socket, acc, timeout) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, data} ->
        read_loop(socket, acc <> data, timeout)

      {:error, :timeout} ->
        acc

      {:error, _reason} ->
        acc
    end
  end
end
