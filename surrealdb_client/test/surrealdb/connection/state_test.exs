defmodule SurrealDB.Connection.StateTest do
  use ExUnit.Case, async: true

  alias SurrealDB.Connection.State

  describe "new/1" do
    test "creates empty state with config" do
      state = State.new(hostname: "localhost")
      assert state.pending == %{}
      assert state.lq_running == %{}
      assert state.lq_sql == MapSet.new()
      assert state.auth_ready == false
      assert state.config[:hostname] == "localhost"
    end
  end

  describe "task lifecycle" do
    test "register, get, delete" do
      state = State.new([])
      task = %{pid: self()}
      state = State.register_task(state, "abc", task)
      assert State.get_task(state, "abc") == task
      state = State.delete_task(state, "abc")
      assert State.get_task(state, "abc") == nil
    end
  end

  describe "live query lifecycle" do
    test "register, get, delete" do
      state = State.new([])
      callback = fn _, _ -> :ok end

      state = State.register_live_query(state, "LIVE SELECT * FROM user", "uuid-1", callback)
      assert State.get_live_query(state, "uuid-1") == %{sql: "LIVE SELECT * FROM user", query_id: "uuid-1", callback: callback}

      state = State.delete_live_query(state, "uuid-1")
      assert State.get_live_query(state, "uuid-1") == nil
    end

    test "tracks SQL for re-subscription" do
      state = State.new([])
      cb1 = fn _, _ -> :a end
      cb2 = fn _, _ -> :b end

      state = State.register_live_query(state, "LIVE SELECT * FROM user", "u1", cb1)
      state = State.register_live_query(state, "LIVE SELECT * FROM post", "u2", cb2)

      queries = State.all_live_queries(state)
      assert length(queries) == 2
      assert {"LIVE SELECT * FROM user", cb1} in queries
      assert {"LIVE SELECT * FROM post", cb2} in queries
    end

    test "reset clears all live queries" do
      state = State.new([])
      state = State.register_live_query(state, "LIVE SELECT * FROM user", "u1", fn _, _ -> :ok end)
      state = State.reset_live_queries(state)
      assert State.all_live_queries(state) == []
    end
  end

  describe "auth ready" do
    test "set and unset" do
      state = State.new([])
      assert state.auth_ready == false
      state = State.set_auth_ready(state, true)
      assert state.auth_ready == true
    end
  end
end
