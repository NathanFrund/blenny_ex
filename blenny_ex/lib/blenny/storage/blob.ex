defmodule Blenny.Storage.Blob do
  @moduledoc """
  Behaviour for blob stores — mirrors the TypeScript `BlobStore` interface.

  Stores binary payloads under `{prefix}/{id}` keys. Used for avatars,
  file uploads, and media assets.
  """

  @typedoc """
  A retrieved blob with data and MIME type.
  """
  @type blob :: %{required(:data) => binary(), required(:mime_type) => String.t()}

  @doc "Stores a blob and returns `{:ok, key}` where key is `\"prefix:id\"`."
  @callback set(
              pid(),
              prefix :: String.t(),
              id :: String.t(),
              data :: binary(),
              mime_type :: String.t()
            ) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Retrieves a blob by prefix and id."
  @callback get(pid(), prefix :: String.t(), id :: String.t()) ::
              {:ok, blob()} | {:error, term()}

  @doc "Removes a blob."
  @callback remove(pid(), prefix :: String.t(), id :: String.t()) :: :ok | {:error, term()}

  @doc "Starts the store as a GenServer."
  @callback start_link(opts :: keyword()) :: GenServer.on_start()
end
