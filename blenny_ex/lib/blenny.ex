defmodule Blenny do
  @moduledoc """
  Blenny — a multi-transport hypermedia engine for Elixir and Phoenix.

  Blenny lets you write unified HTML components that can be delivered over
  Server-Sent Events (via Datastar) or Phoenix LiveView WebSockets, routing
  transport based on the client's runtime environment.

  ## Modules

  Modules implement the `Blenny.Module` behaviour and are automatically
  discovered at compile time. See `Blenny.Module` for details.

  ## Publisher

  The `Blenny.Publisher` provides a zero-ceremony API for broadcasting or
  directly sending HTML fragments, signal data, or scripts to connected clients.

      Blenny.Publisher.broadcast_html(~s|<div id="status">Updated</div>|)
      Blenny.Publisher.direct_data(~s|{"score": 42}|, user_id)
  """

  @doc """
  Returns the configured PubSub module for the host application.

  Set via:

      config :blenny_ex, pub_sub: MyApp.PubSub
  """
  def pub_sub do
    Application.get_env(:blenny_ex, :pub_sub) ||
      raise """
      Blenny requires a PubSub module configured.
      Set in your config.exs:

          config :blenny_ex, pub_sub: MyApp.PubSub
      """
  end
end
