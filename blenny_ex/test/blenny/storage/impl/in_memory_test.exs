defmodule Blenny.Storage.Impl.InMemoryTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = Blenny.Storage.Impl.InMemory.start_link([])
    on_exit(fn -> Blenny.Storage.Impl.InMemory.stop(pid) end)
    %{pid: pid}
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
      assert Blenny.Storage.Impl.InMemory.find_by_id(pid, "nonexistent") == nil
    end

    test "returns user after creation", %{pid: pid} do
      {:ok, user} = Blenny.Storage.Impl.InMemory.create_user(pid, user_attrs())
      assert Blenny.Storage.Impl.InMemory.find_by_id(pid, user.id) == user
    end
  end

  describe "find_by_username/2" do
    test "returns nil for missing username", %{pid: pid} do
      assert Blenny.Storage.Impl.InMemory.find_by_username(pid, "nobody") == nil
    end

    test "returns user after creation", %{pid: pid} do
      {:ok, user} = Blenny.Storage.Impl.InMemory.create_user(pid, user_attrs())
      assert Blenny.Storage.Impl.InMemory.find_by_username(pid, "alice") == user
    end
  end

  describe "create_user/2" do
    test "returns {:ok, user} with generated id and created_at", %{pid: pid} do
      {:ok, user} = Blenny.Storage.Impl.InMemory.create_user(pid, user_attrs())

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
      {:ok, user} = Blenny.Storage.Impl.InMemory.create_user(pid, user_attrs(role: nil))
      assert user.role == "user"
    end

    test "returns {:error, :already_exists} for duplicate username", %{pid: pid} do
      {:ok, _user} = Blenny.Storage.Impl.InMemory.create_user(pid, user_attrs())

      assert Blenny.Storage.Impl.InMemory.create_user(pid, user_attrs()) ==
               {:error, :already_exists}
    end

    test "allows different usernames", %{pid: pid} do
      {:ok, _u1} = Blenny.Storage.Impl.InMemory.create_user(pid, user_attrs(username: "alice"))
      {:ok, _u2} = Blenny.Storage.Impl.InMemory.create_user(pid, user_attrs(username: "bob"))
      assert Blenny.Storage.Impl.InMemory.find_by_username(pid, "alice") != nil
      assert Blenny.Storage.Impl.InMemory.find_by_username(pid, "bob") != nil
    end
  end

  describe "update_password_hash/3" do
    test "updates the hash for existing user", %{pid: pid} do
      {:ok, user} = Blenny.Storage.Impl.InMemory.create_user(pid, user_attrs())
      :ok = Blenny.Storage.Impl.InMemory.update_password_hash(pid, user.id, "new_hash")
      updated = Blenny.Storage.Impl.InMemory.find_by_id(pid, user.id)
      assert updated.password_hash == "new_hash"
    end

    test "returns error for missing user", %{pid: pid} do
      assert Blenny.Storage.Impl.InMemory.update_password_hash(pid, "nobody", "hash") ==
               {:error, :not_found}
    end
  end

  describe "update_avatar_key/3" do
    test "sets avatar key on existing user", %{pid: pid} do
      {:ok, user} = Blenny.Storage.Impl.InMemory.create_user(pid, user_attrs())
      :ok = Blenny.Storage.Impl.InMemory.update_avatar_key(pid, user.id, "avatars:abc123")
      updated = Blenny.Storage.Impl.InMemory.find_by_id(pid, user.id)
      assert updated.avatar_key == "avatars:abc123"
    end

    test "returns error for missing user", %{pid: pid} do
      assert Blenny.Storage.Impl.InMemory.update_avatar_key(pid, "nobody", "key") ==
               {:error, :not_found}
    end
  end

  describe "delete_user/2" do
    test "removes user from both tables", %{pid: pid} do
      {:ok, user} = Blenny.Storage.Impl.InMemory.create_user(pid, user_attrs())
      :ok = Blenny.Storage.Impl.InMemory.delete_user(pid, user.id)

      assert Blenny.Storage.Impl.InMemory.find_by_id(pid, user.id) == nil
      assert Blenny.Storage.Impl.InMemory.find_by_username(pid, "alice") == nil
    end

    test "returns error for missing user", %{pid: pid} do
      assert Blenny.Storage.Impl.InMemory.delete_user(pid, "nobody") == {:error, :not_found}
    end
  end

  describe "stop/1" do
    test "cleans up ETS tables", %{pid: pid} do
      Blenny.Storage.Impl.InMemory.stop(pid)
      assert :ets.info(:blenny_storage_in_memory) == :undefined
      assert :ets.info(:blenny_storage_in_memory_uname) == :undefined
    end
  end
end
