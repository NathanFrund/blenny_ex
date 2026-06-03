defmodule Blenny.ErrorTest do
  use ExUnit.Case, async: true

  test "new/2 creates an error without status" do
    err = Blenny.Error.new(:not_found, "module not found")
    assert err.type == :not_found
    assert err.message == "module not found"
    assert err.status == nil
    assert Exception.message(err) == "module not found"
  end

  test "new/3 creates an error with status" do
    err = Blenny.Error.new(:too_many_connections, "connection limit reached", 503)
    assert err.type == :too_many_connections
    assert err.status == 503
    assert Exception.message(err) == "connection limit reached"
  end
end
