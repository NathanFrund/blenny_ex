defmodule Blenny.Storage.UUID do
  @moduledoc """
  RFC 4122 compliant UUIDv4 generation without external dependencies.

  Uses `:crypto.strong_rand_bytes/1` for cryptographically secure random
  bytes, then sets version (4) and variant (RFC 4122) bits per the spec.
  """

  @doc """
  Generates a standard RFC 4122 compliant UUIDv4 string.

  ## Examples

      iex> uuid = Blenny.Storage.UUID.generate()
      iex> String.match?(uuid, ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
      true
  """
  def generate do
    <<u0::48, _v::4, u1::12, _r::2, u2::62>> = :crypto.strong_rand_bytes(16)

    <<u0::48, 4::4, u1::12, 2::2, u2::62>>
    |> Base.encode16(case: :lower)
    |> format()
  end

  defp format(
         <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
           e::binary-size(12)>>
       ) do
    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end
end
