defmodule Blenny.Storage.Impl.FSBlob do
  @moduledoc """
  Filesystem-backed blob store.

  Stores binary payloads as files on disk with a companion `.type` file
  for MIME type metadata. Replicates the TypeScript `FsBlobStore`.

  ## File layout

      <base_dir>/<prefix>/<id>        — raw binary data
      <base_dir>/<prefix>/<id>.type   — MIME type string

  ## Usage

      {:ok, pid} = Blenny.Storage.Impl.FSBlob.start_link(base_dir: "./data/blobs")
      {:ok, key} = Blenny.Storage.Impl.FSBlob.set(pid, "avatars", user_id, image_binary, "image/png")
  """

  @behaviour Blenny.Storage.Blob
  use GenServer

  # ── Public API ──────────────────────────────────────────────────────

  @impl true
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def set(pid, prefix, id, data, mime_type) do
    GenServer.call(pid, {:set, prefix, id, data, mime_type})
  end

  @impl true
  def get(pid, prefix, id) do
    GenServer.call(pid, {:get, prefix, id})
  end

  @impl true
  def remove(pid, prefix, id) do
    GenServer.call(pid, {:remove, prefix, id})
  end

  # ── GenServer callbacks ────────────────────────────────────────────

  @impl true
  def init(opts) do
    base_dir = Keyword.get(opts, :base_dir, "./data/blobs")
    File.mkdir_p!(base_dir)
    {:ok, %{base_dir: base_dir}}
  end

  @impl true
  def handle_call({:set, prefix, id, data, mime_type}, _from, state) do
    dir = Path.join(state.base_dir, prefix)
    File.mkdir_p!(dir)

    File.write!(Path.join(dir, id), data)
    File.write!(Path.join(dir, "#{id}.type"), mime_type)

    {:reply, {:ok, "#{prefix}:#{id}"}, state}
  end

  @impl true
  def handle_call({:get, prefix, id}, _from, state) do
    data_path = Path.join([state.base_dir, prefix, id])
    type_path = Path.join([state.base_dir, prefix, "#{id}.type"])

    result =
      case File.read(data_path) do
        {:ok, data} ->
          case File.read(type_path) do
            {:ok, mime_type} -> {:ok, %{data: data, mime_type: mime_type}}
            _ -> {:error, :corrupt}
          end

        {:error, reason} ->
          {:error, reason}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:remove, prefix, id}, _from, state) do
    File.rm(Path.join([state.base_dir, prefix, id]))
    File.rm(Path.join([state.base_dir, prefix, "#{id}.type"]))
    {:reply, :ok, state}
  end
end
