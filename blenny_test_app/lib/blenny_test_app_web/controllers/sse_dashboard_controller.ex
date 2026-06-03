defmodule BlennyTestAppWeb.SSEDashboardController do
  use BlennyTestAppWeb, :controller

  def index(conn, _params) do
    now = BlennyTestApp.Time.now()

    render(conn, :index,
      cpu: 0,
      mem: 0,
      time: now |> Calendar.strftime("%H:%M:%S")
    )
  end
end
