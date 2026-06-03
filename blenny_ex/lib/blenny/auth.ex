defmodule Blenny.Auth do
  @moduledoc """
  User identity token set by the active auth provider.

  Set in `conn.assigns.blenny_auth` by `Blenny.Plug.FetchSession`
  on every authenticated request.
  """

  defstruct [:id, :role, metadata: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          role: String.t(),
          metadata: map()
        }
end
