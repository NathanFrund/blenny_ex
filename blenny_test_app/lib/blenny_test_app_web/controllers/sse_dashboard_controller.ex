defmodule BlennyTestAppWeb.SSEDashboardController do
  use BlennyTestAppWeb, :controller

  def index(conn, _params) do
    render(conn, :index,
      cpu: 0,
      mem: 0,
      time: DateTime.utc_now() |> Calendar.strftime("%H:%M:%S")
    )
  end
end
