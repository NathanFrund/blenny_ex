defmodule SurrealDB.Protocol do
  @moduledoc """
  Builds and parses JSON messages for the SurrealDB WebSocket RPC protocol.

  Every message follows the JSON-RPC-like format:
    `{"id": "uuid", "method": "method_name", "params": [...]}`
  """

  @doc "Generates a unique request ID."
  def request_id do
    <<i::64, j::64>> = :crypto.strong_rand_bytes(16)
    Integer.to_string(i, 36) <> Integer.to_string(j, 36)
  end

  @doc "Builds a JSON-encoded RPC payload for the given method and args."
  def build_payload(method, args, id \\ nil) do
    id = id || request_id()
    params = build_params(method, args)
    body = %{"id" => id, "method" => method, "params" => params}
    {id, Jason.encode!(body)}
  end

  @doc "Parses a JSON response from SurrealDB."
  def parse_response(json) do
    case Jason.decode(json) do
      {:ok, msg} ->
        cond do
          is_map(msg) && Map.has_key?(msg, "error") -> {:error, msg["error"]}
          true -> {:ok, msg}
        end

      {:error, reason} ->
        {:error, {:invalid_json, reason}}
    end
  end

  defp build_params("ping", _), do: []
  defp build_params("use", args), do: [args[:ns], args[:db]]
  defp build_params("info", _), do: []
  defp build_params("signin", args), do: [args[:payload]]
  defp build_params("signup", args), do: [args[:payload]]
  defp build_params("authenticate", args), do: [args[:token]]
  defp build_params("invalidate", _), do: []
  defp build_params("let", args), do: [args[:name], args[:value]]
  defp build_params("unset", args), do: [args[:name]]
  defp build_params("live", args), do: [args[:table]]
  defp build_params("kill", args), do: [args[:query_uuid]]
  defp build_params("query", args), do: [args[:sql], args[:vars] || %{}]
  defp build_params("select", args), do: [args[:thing]]
  defp build_params("create", args), do: [args[:thing], args[:data] || %{}]
  defp build_params("insert", args), do: [args[:thing], args[:data] || %{}]
  defp build_params("update", args), do: [args[:thing], args[:data] || %{}]
  defp build_params("merge", args), do: [args[:thing], args[:data] || %{}]
  defp build_params("delete", args), do: [args[:thing]]
end
