defmodule Blenny.PublisherTest do
  use ExUnit.Case, async: false

  @pubsub_name :"test_pubsub_#{System.unique_integer([:positive])}"

  setup do
    start_supervised!({Phoenix.PubSub, name: @pubsub_name})

    Application.put_env(:blenny_ex, :pub_sub, @pubsub_name)
    on_exit(fn -> Application.delete_env(:blenny_ex, :pub_sub) end)

    :ok
  end

  test "broadcast_html publishes to :ui intent topic" do
    Phoenix.PubSub.subscribe(@pubsub_name, "blenny:intent:ui")
    Blenny.Publisher.broadcast_html("<div>hello</div>")

    assert_receive {:blenny_msg, :ui, %{html: "<div>hello</div>"}}
  end

  test "broadcast_data with map publishes to :ui intent topic" do
    Phoenix.PubSub.subscribe(@pubsub_name, "blenny:intent:ui")
    Blenny.Publisher.broadcast_data(%{"cpu" => 42, "mem" => 128})

    assert_receive {:blenny_msg, :ui, %{signals: %{"cpu" => 42, "mem" => 128}}}
  end

  test "broadcast_data with JSON string decodes and publishes" do
    Phoenix.PubSub.subscribe(@pubsub_name, "blenny:intent:ui")
    Blenny.Publisher.broadcast_data(~s|{"cpu": 42}|)

    assert_receive {:blenny_msg, :ui, %{signals: %{"cpu" => 42}}}
  end

  test "direct_html sends to user topic" do
    Phoenix.PubSub.subscribe(@pubsub_name, "blenny:user:user-1")
    Blenny.Publisher.direct_html("<div>private</div>", "user-1")

    assert_receive {:blenny_msg, :direct, %{html: "<div>private</div>"}}
  end

  test "direct_data sends to user topic" do
    Phoenix.PubSub.subscribe(@pubsub_name, "blenny:user:user-2")
    Blenny.Publisher.direct_data(%{"score" => 100}, "user-2")

    assert_receive {:blenny_msg, :direct, %{signals: %{"score" => 100}}}
  end

  test "direct_data with JSON string decodes" do
    Phoenix.PubSub.subscribe(@pubsub_name, "blenny:user:user-3")
    Blenny.Publisher.direct_data(~s|{"score": 200}|, "user-3")

    assert_receive {:blenny_msg, :direct, %{signals: %{"score" => 200}}}
  end

  test "execute_script publishes to :command intent topic" do
    Phoenix.PubSub.subscribe(@pubsub_name, "blenny:intent:command")
    Blenny.Publisher.execute_script("console.log('test')")

    assert_receive {:blenny_msg, :command, %{script: "console.log('test')"}}
  end

  test "broadcast to :ui does not reach :command subscribers" do
    Phoenix.PubSub.subscribe(@pubsub_name, "blenny:intent:command")
    Phoenix.PubSub.subscribe(@pubsub_name, "blenny:intent:ui")

    Blenny.Publisher.broadcast_data(%{"cpu" => 1})

    assert_receive {:blenny_msg, :ui, _}
    refute_receive {:blenny_msg, :command, _}
  end

  test "html and data don't cross-contaminate" do
    Phoenix.PubSub.subscribe(@pubsub_name, "blenny:intent:ui")

    Blenny.Publisher.broadcast_html("<div>only html</div>")
    assert_receive {:blenny_msg, :ui, %{html: _}}

    Blenny.Publisher.broadcast_data(%{"key" => "only data"})
    assert_receive {:blenny_msg, :ui, %{signals: _}}
  end
end
