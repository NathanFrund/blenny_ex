defmodule Blenny.Error do
  @moduledoc """
  A structured exception for Blenny errors.

  Carries a machine-readable `:type` atom, a human-readable `:message`, and an
  optional HTTP `:status` code.
  """

  defexception [:type, :message, :status]

  @type t :: %__MODULE__{
          type: atom(),
          message: String.t(),
          status: non_neg_integer() | nil
        }

  @doc """
  Creates a new Blenny.Error.

  ## Examples

      Blenny.Error.new(:too_many_connections, "connection limit reached", 503)
      Blenny.Error.new(:not_found, "module not found")
  """
  @spec new(atom(), String.t(), non_neg_integer() | nil) :: t()
  def new(type, message, status \\ nil) do
    %__MODULE__{type: type, message: message, status: status}
  end

  @impl true
  def message(%__MODULE__{message: msg}), do: msg
end
