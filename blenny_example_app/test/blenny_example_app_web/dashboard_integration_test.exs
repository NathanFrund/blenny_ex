defmodule BlennyExampleAppWeb.DashboardIntegrationTest do
  use BlennyExampleAppWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "renders initial state with zero values and empty event log", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, BlennyExampleAppWeb.DashboardLive)
    assert has_element?(view, "#cpu", "0%")
    assert has_element?(view, "#mem", "0 MB")
    assert has_element?(view, "#time")
    assert has_element?(view, "#event-log")
    assert has_element?(view, "#event-log", "No events yet")
  end

  test "receives signal data from Publisher via PubSub and logs event", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, BlennyExampleAppWeb.DashboardLive)

    Blenny.Publisher.broadcast_data(%{
      "cpu" => 42.1,
      "mem" => 128.5,
      "time" => "12:00:00"
    })

    :timer.sleep(100)

    html = render(view)
    assert html =~ "42.1%"
    assert html =~ "128.5 MB"
    assert html =~ "12:00:00"

    # Event log should contain the signal update
    assert html =~ "CPU 42.1%"
  end

  test "ignores HTML fragments (intended for SSE clients)", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, BlennyExampleAppWeb.DashboardLive)

    Blenny.Publisher.broadcast_html(~s|<div id="test-fragment">Hello from Blenny</div>|)

    :timer.sleep(100)

    # LiveView handle_info only processes signals, not HTML — no crash, no change
    html = render(view)
    refute html =~ "test-fragment"
  end

  test "displays broadcast send button", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, BlennyExampleAppWeb.DashboardLive)
    assert has_element?(view, "button", "Send HTML")
    assert has_element?(view, "button", "Send Data")
    assert has_element?(view, "button", "Send Script")
  end
end
