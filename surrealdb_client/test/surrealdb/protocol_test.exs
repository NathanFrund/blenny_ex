defmodule SurrealDB.ProtocolTest do
  use ExUnit.Case, async: true

  alias SurrealDB.Protocol

  describe "build_payload/3" do
    test "builds a ping payload" do
      {id, json} = Protocol.build_payload("ping", [])
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["method"] == "ping"
      assert decoded["params"] == []
      assert decoded["id"] == id
    end

    test "builds a query payload with vars" do
      {id, json} =
        Protocol.build_payload("query",
          sql: "SELECT * FROM user WHERE status = $1",
          vars: %{"status" => "active"}
        )

      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["method"] == "query"

      assert decoded["params"] == [
               "SELECT * FROM user WHERE status = $1",
               %{"status" => "active"}
             ]

      assert decoded["id"] == id
    end

    test "builds a signin payload" do
      {id, json} = Protocol.build_payload("signin", payload: %{user: "root", pass: "root"})
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["method"] == "signin"
      assert decoded["params"] == [%{"user" => "root", "pass" => "root"}]
      assert decoded["id"] == id
    end

    test "builds a use payload" do
      {id, json} = Protocol.build_payload("use", ns: "test", db: "app")
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["method"] == "use"
      assert decoded["params"] == ["test", "app"]
      assert decoded["id"] == id
    end

    test "builds a create payload" do
      {id, json} = Protocol.build_payload("create", thing: "user", data: %{name: "Alice"})
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["method"] == "create"
      assert decoded["params"] == ["user", %{"name" => "Alice"}]
      assert decoded["id"] == id
    end

    test "builds a delete payload" do
      {id, json} = Protocol.build_payload("delete", thing: "user:abc123")
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["method"] == "delete"
      assert decoded["params"] == ["user:abc123"]
      assert decoded["id"] == id
    end

    test "builds a kill payload" do
      {id, json} = Protocol.build_payload("kill", query_uuid: "abc-def")
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["method"] == "kill"
      assert decoded["params"] == ["abc-def"]
      assert decoded["id"] == id
    end
  end

  describe "request_id/0" do
    test "generates unique IDs" do
      ids = for _ <- 1..100, do: Protocol.request_id()
      assert length(Enum.uniq(ids)) == 100
    end

    test "generates string IDs" do
      assert is_binary(Protocol.request_id())
    end
  end

  describe "parse_response/1" do
    test "parses a valid response" do
      json = ~S({"id":"abc","result":[{"status":"OK","result":[]}]})
      assert {:ok, %{"id" => "abc", "result" => _}} = Protocol.parse_response(json)
    end

    test "parses an error response" do
      json = ~S({"id":"abc","error":"Something went wrong"})
      assert {:error, "Something went wrong"} = Protocol.parse_response(json)
    end

    test "rejects invalid JSON" do
      assert {:error, {:invalid_json, _}} = Protocol.parse_response("not json")
    end
  end
end
