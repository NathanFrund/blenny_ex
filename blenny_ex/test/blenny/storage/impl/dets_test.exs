defmodule Blenny.Storage.Impl.DETSTest do
  use ExUnit.Case, async: false

  setup do
    tmp_dir =
      System.tmp_dir!() |> Path.join("blenny_dets_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    {:ok, pid} = Blenny.Storage.Impl.DETS.start_link(data_dir: tmp_dir)

    on_exit(fn ->
      if Process.alive?(pid), do: Blenny.Storage.Impl.DETS.stop(pid)
      File.rm_rf!(tmp_dir)
    end)

    %{pid: pid, tmp_dir: tmp_dir}
  end

  defp user_attrs(overrides \\ []) do
    %{
      username: Keyword.get(overrides, :username, "alice"),
      password_hash: Keyword.get(overrides, :password_hash, "hashed_pw"),
      display_name: Keyword.get(overrides, :display_name, "Alice"),
      role: Keyword.get(overrides, :role, "user")
    }
  end

  describe "find_by_id/2" do
    test "returns nil for missing user", %{pid: pid} do
      assert Blenny.Storage.Impl.DETS.find_by_id(pid, "nonexistent") == nil
    end

    test "returns user after creation", %{pid: pid} do
      {:ok, user} = Blenny.Storage.Impl.DETS.create_user(pid, user_attrs())
      assert Blenny.Storage.Impl.DETS.find_by_id(pid, user.id) == user
    end
  end

  describe "find_by_username/2" do
    test "returns nil for missing username", %{pid: pid} do
      assert Blenny.Storage.Impl.DETS.find_by_username(pid, "nobody") == nil
    end

    test "returns user after creation", %{pid: pid} do
      {:ok, user} = Blenny.Storage.Impl.DETS.create_user(pid, user_attrs())
      assert Blenny.Storage.Impl.DETS.find_by_username(pid, "alice") == user
    end
  end

  describe "create_user/2" do
    test "returns {:ok, user} with generated id and created_at", %{pid: pid} do
      {:ok, user} = Blenny.Storage.Impl.DETS.create_user(pid, user_attrs())

      assert user.id != nil
      assert user.created_at != nil
      assert is_integer(user.created_at)
      assert user.username == "alice"
      assert user.password_hash == "hashed_pw"
      assert user.display_name == "Alice"
      assert user.role == "user"
      assert user.avatar_key == nil
    end

    test "defaults role to user", %{pid: pid} do
      {:ok, user} = Blenny.Storage.Impl.DETS.create_user(pid, user_attrs(role: nil))
      assert user.role == "user"
    end

    test "returns {:error, :already_exists} for duplicate username", %{pid: pid} do
      {:ok, _} = Blenny.Storage.Impl.DETS.create_user(pid, user_attrs())
      assert Blenny.Storage.Impl.DETS.create_user(pid, user_attrs()) == {:error, :already_exists}
    end

    test "allows different usernames", %{pid: pid} do
      {:ok, _} = Blenny.Storage.Impl.DETS.create_user(pid, user_attrs(username: "alice"))
      {:ok, _} = Blenny.Storage.Impl.DETS.create_user(pid, user_attrs(username: "bob"))
      assert Blenny.Storage.Impl.DETS.find_by_username(pid, "alice") != nil
      assert Blenny.Storage.Impl.DETS.find_by_username(pid, "bob") != nil
    end
  end

  describe "update_password_hash/3" do
    test "updates the hash for existing user", %{pid: pid} do
      {:ok, user} = Blenny.Storage.Impl.DETS.create_user(pid, user_attrs())
      :ok = Blenny.Storage.Impl.DETS.update_password_hash(pid, user.id, "new_hash")
      updated = Blenny.Storage.Impl.DETS.find_by_id(pid, user.id)
      assert updated.password_hash == "new_hash"
    end

    test "returns error for missing user", %{pid: pid} do
      assert Blenny.Storage.Impl.DETS.update_password_hash(pid, "nobody", "hash") ==
               {:error, :not_found}
    end
  end

  describe "update_avatar_key/3" do
    test "sets avatar key on existing user", %{pid: pid} do
      {:ok, user} = Blenny.Storage.Impl.DETS.create_user(pid, user_attrs())
      :ok = Blenny.Storage.Impl.DETS.update_avatar_key(pid, user.id, "avatars:abc123")
      updated = Blenny.Storage.Impl.DETS.find_by_id(pid, user.id)
      assert updated.avatar_key == "avatars:abc123"
    end

    test "returns error for missing user", %{pid: pid} do
      assert Blenny.Storage.Impl.DETS.update_avatar_key(pid, "nobody", "key") ==
               {:error, :not_found}
    end
  end

  describe "delete_user/2" do
    test "removes user from both tables", %{pid: pid} do
      {:ok, user} = Blenny.Storage.Impl.DETS.create_user(pid, user_attrs())
      :ok = Blenny.Storage.Impl.DETS.delete_user(pid, user.id)

      assert Blenny.Storage.Impl.DETS.find_by_id(pid, user.id) == nil
      assert Blenny.Storage.Impl.DETS.find_by_username(pid, "alice") == nil
    end

    test "returns error for missing user", %{pid: pid} do
      assert Blenny.Storage.Impl.DETS.delete_user(pid, "nobody") == {:error, :not_found}
    end
  end

  describe "data persistence across restart" do
    test "survives GenServer stop and start", %{tmp_dir: tmp_dir} do
      {:ok, pid1} = Blenny.Storage.Impl.DETS.start_link(data_dir: tmp_dir)
      {:ok, _user} = Blenny.Storage.Impl.DETS.create_user(pid1, user_attrs(username: "persist"))
      Blenny.Storage.Impl.DETS.stop(pid1)

      {:ok, pid2} = Blenny.Storage.Impl.DETS.start_link(data_dir: tmp_dir)
      found = Blenny.Storage.Impl.DETS.find_by_username(pid2, "persist")
      assert found != nil
      assert found.username == "persist"

      Blenny.Storage.Impl.DETS.stop(pid2)
    end
  end
end
