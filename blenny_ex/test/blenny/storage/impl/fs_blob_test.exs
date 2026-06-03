defmodule Blenny.Storage.Impl.FSBlobTest do
  use ExUnit.Case, async: false

  setup do
    tmp_dir =
      System.tmp_dir!() |> Path.join("blenny_fsblob_test_#{System.unique_integer([:positive])}")

    {:ok, pid} = Blenny.Storage.Impl.FSBlob.start_link(base_dir: tmp_dir)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :shutdown)
      File.rm_rf!(tmp_dir)
    end)

    %{pid: pid, tmp_dir: tmp_dir}
  end

  describe "set/5" do
    test "stores data and type file", %{pid: pid, tmp_dir: tmp_dir} do
      {:ok, key} =
        Blenny.Storage.Impl.FSBlob.set(pid, "avatars", "user1", "image_data", "image/png")

      assert key == "avatars:user1"

      assert File.read!(Path.join([tmp_dir, "avatars", "user1"])) == "image_data"
      assert File.read!(Path.join([tmp_dir, "avatars", "user1.type"])) == "image/png"
    end

    test "creates prefix directories automatically", %{pid: pid, tmp_dir: tmp_dir} do
      {:ok, _key} =
        Blenny.Storage.Impl.FSBlob.set(pid, "deep/nested", "file1", "data", "text/plain")

      assert File.dir?(Path.join([tmp_dir, "deep", "nested"]))
      assert File.read!(Path.join([tmp_dir, "deep", "nested", "file1"])) == "data"
    end
  end

  describe "get/3" do
    test "retrieves stored data and mime type", %{pid: pid} do
      {:ok, _key} =
        Blenny.Storage.Impl.FSBlob.set(pid, "avatars", "user1", "png_data", "image/png")

      {:ok, blob} = Blenny.Storage.Impl.FSBlob.get(pid, "avatars", "user1")
      assert blob.data == "png_data"
      assert blob.mime_type == "image/png"
    end

    test "returns error for missing blob", %{pid: pid} do
      {:error, _reason} = Blenny.Storage.Impl.FSBlob.get(pid, "avatars", "nonexistent")
    end

    test "returns error when type file is missing", %{pid: pid, tmp_dir: tmp_dir} do
      {:ok, _key} = Blenny.Storage.Impl.FSBlob.set(pid, "avatars", "bad", "data", "text/plain")
      File.rm!(Path.join([tmp_dir, "avatars", "bad.type"]))

      assert Blenny.Storage.Impl.FSBlob.get(pid, "avatars", "bad") == {:error, :corrupt}
    end
  end

  describe "remove/3" do
    test "deletes both files", %{pid: pid, tmp_dir: tmp_dir} do
      {:ok, _key} = Blenny.Storage.Impl.FSBlob.set(pid, "avatars", "user1", "data", "image/png")
      :ok = Blenny.Storage.Impl.FSBlob.remove(pid, "avatars", "user1")

      refute File.exists?(Path.join([tmp_dir, "avatars", "user1"]))
      refute File.exists?(Path.join([tmp_dir, "avatars", "user1.type"]))
    end

    test "is idempotent", %{pid: pid} do
      assert Blenny.Storage.Impl.FSBlob.remove(pid, "avatars", "nonexistent") == :ok
      assert Blenny.Storage.Impl.FSBlob.remove(pid, "avatars", "nonexistent") == :ok
    end
  end

  describe "prefix isolation" do
    test "different prefixes are isolated", %{pid: pid} do
      {:ok, _} = Blenny.Storage.Impl.FSBlob.set(pid, "avatars", "user1", "img_data", "image/png")

      {:ok, _} =
        Blenny.Storage.Impl.FSBlob.set(pid, "documents", "user1", "doc_data", "text/plain")

      {:ok, blob} = Blenny.Storage.Impl.FSBlob.get(pid, "avatars", "user1")
      assert blob.data == "img_data"

      {:ok, blob} = Blenny.Storage.Impl.FSBlob.get(pid, "documents", "user1")
      assert blob.data == "doc_data"
    end
  end
end
