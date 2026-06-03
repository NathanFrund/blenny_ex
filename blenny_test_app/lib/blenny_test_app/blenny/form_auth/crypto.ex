defmodule BlennyTestApp.Blenny.FormAuth.Crypto do
  @moduledoc """
  PBKDF2 key derivation matching the TypeScript form-auth module.

  Uses `:crypto.pbkdf2_hmac/5` with SHA-256, 100,000 iterations,
  32-byte output, hex-encoded — zero external dependencies.
  """

  @doc """
  Derives a hex-encoded key from a password and salt using PBKDF2-HMAC-SHA256.

  ## Examples

      iex> hash = BlennyTestApp.Blenny.FormAuth.Crypto.derive_key("password", "salt")
      iex> String.match?(hash, ~r/^[0-9a-f]{64}$/)
      true

      iex> BlennyTestApp.Blenny.FormAuth.Crypto.derive_key("same", "salt") ==
      ...> BlennyTestApp.Blenny.FormAuth.Crypto.derive_key("same", "salt")
      true

      iex> BlennyTestApp.Blenny.FormAuth.Crypto.derive_key("diff", "salt") !=
      ...> BlennyTestApp.Blenny.FormAuth.Crypto.derive_key("same", "salt")
      true
  """
  def derive_key(password, salt) do
    :crypto.pbkdf2_hmac(:sha256, password, salt, 100_000, 32)
    |> Base.encode16(case: :lower)
  end
end
