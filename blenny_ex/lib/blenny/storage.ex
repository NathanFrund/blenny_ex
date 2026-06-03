defmodule Blenny.Storage do
  @moduledoc """
  Behaviour-based storage layer for Blenny modules.

  Provides durable, dependency-free storage using Erlang/OTP built-in
  engines — ETS for ephemeral speed (dev/test) and DETS for zero-overhead
  persistence (single-node production).

  ## Behaviours

    * `Blenny.Storage.User` — user CRUD operations (`find_by_username`,
      `create_user`, etc.)

    * `Blenny.Storage.Blob` — binary blob storage (`set`, `get`, `remove`)

  ## Built-in implementations

  | Implementation | Backend | Durable | Best for |
  |---|---|---|---|
  | `Blenny.Storage.Impl.InMemory` | ETS | — | Dev/test (default) |
  | `Blenny.Storage.Impl.DETS` | DETS | Yes | Single-node production |
  | `Blenny.Storage.Impl.FSBlob` | Filesystem | Yes | Avatars, media blobs |

  Modules choose their store at `init/1` time via config, following the same
  `form-auth.store` pattern as the TypeScript version.
  """
end
