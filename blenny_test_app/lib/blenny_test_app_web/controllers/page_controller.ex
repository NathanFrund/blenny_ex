defmodule BlennyTestAppWeb.PageController do
  use BlennyTestAppWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
