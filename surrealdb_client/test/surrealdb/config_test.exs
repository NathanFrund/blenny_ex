defmodule SurrealDB.ConfigTest do
  use ExUnit.Case, async: true

  describe "compile/1" do
    test "applies defaults" do
      config = SurrealDB.Config.compile([])
      assert config[:hostname] == "localhost"
      assert config[:port] == 8000
      assert config[:username] == "root"
      assert config[:password] == "root"
      assert config[:namespace] == "test"
      assert config[:database] == "test"
      assert config[:query_timeout] == 5_000
      assert config[:backoff_max] == 10_000
    end

    test "merges user options over defaults" do
      config =
        SurrealDB.Config.compile(
          hostname: "db.example.com",
          port: 9000,
          username: "admin",
          namespace: "prod",
          database: "app"
        )

      assert config[:hostname] == "db.example.com"
      assert config[:port] == 9000
      assert config[:username] == "admin"
      assert config[:namespace] == "prod"
      assert config[:database] == "app"
    end

    test "raises on invalid key" do
      assert_raise NimbleOptions.ValidationError, fn ->
        SurrealDB.Config.compile(invalid_key: "value")
      end
    end

    test "raises on wrong type" do
      assert_raise NimbleOptions.ValidationError, fn ->
        SurrealDB.Config.compile(port: "not_a_number")
      end
    end
  end
end
