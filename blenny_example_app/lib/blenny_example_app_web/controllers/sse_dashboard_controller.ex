defmodule BlennyExampleAppWeb.SSEDashboardController do
  use BlennyExampleAppWeb, :controller

  def index(conn, _params) do
    now = BlennyExampleApp.Time.now()

    render(conn, :index,
      cpu: 0,
      mem: 0,
      time: now |> Calendar.strftime("%H:%M:%S")
    )
  end
end
