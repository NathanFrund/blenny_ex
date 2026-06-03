defmodule Blenny.Test.SSEEndpoint do
  use Plug.Builder

  plug(:fetch_query_params)
  plug(Blenny.Transport.SSEPlug)
end
