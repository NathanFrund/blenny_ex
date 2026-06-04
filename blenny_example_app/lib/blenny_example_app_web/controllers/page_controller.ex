defmodule BlennyExampleAppWeb.PageController do
  use BlennyExampleAppWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
