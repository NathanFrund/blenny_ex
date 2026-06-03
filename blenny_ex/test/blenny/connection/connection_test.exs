defmodule Blenny.ConnectionTest do
  use ExUnit.Case, async: true

  test "new/3 creates a connection with default fields" do
    conn = Blenny.Connection.new("conn-1", :liveview)

    assert conn.id == "conn-1"
    assert conn.conn_type == :liveview
    assert conn.user_id == nil
    assert conn.transport_pid == nil
    assert conn.intents == []
    assert is_integer(conn.inserted_at)
    assert conn.inserted_at > 0
  end

  test "new/3 accepts opts" do
    pid = self()

    conn =
      Blenny.Connection.new("conn-2", :sse,
        user_id: "user-1",
        transport_pid: pid,
        intents: [:ui, :command]
      )

    assert conn.id == "conn-2"
    assert conn.conn_type == :sse
    assert conn.user_id == "user-1"
    assert conn.transport_pid == pid
    assert conn.intents == [:ui, :command]
  end

  test "new/3 uses current time for inserted_at" do
    before = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    conn = Blenny.Connection.new("conn-3", :liveview)
    after_ = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    assert conn.inserted_at >= before
    assert conn.inserted_at <= after_
  end
end
