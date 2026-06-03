# Ensure :pg scope is available for Phoenix.PubSub.PG2
# (normally started by the phoenix_pubsub application, which
# is skipped when running with --no-start)
case :pg.start_link(Phoenix.PubSub) do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
end

ExUnit.start()
