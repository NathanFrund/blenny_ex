defmodule BlennyTestApp.Time do
  @moduledoc false

  @doc """
  Returns a NaiveDateTime in the system's local timezone.
  """
  def now do
    {{y, m, d}, {h, mi, s}} = :calendar.local_time()
    %NaiveDateTime{year: y, month: m, day: d, hour: h, minute: mi, second: s}
  end

  @doc """
  Formats the current local time as "HH:MM:SS".
  """
  def format_timestamp do
    now() |> Calendar.strftime("%H:%M:%S")
  end

  @doc """
  Converts a Unix millisecond timestamp to a local time "HH:MM:SS" string.
  """
  def from_unix_ms(ts) when is_integer(ts) do
    utc_s = div(ts, 1000)
    epoch = :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})
    local_s = utc_s + :erlang.time_offset()
    {{_y, _m, _d}, {h, mi, s}} = :calendar.gregorian_seconds_to_datetime(local_s + epoch)
    pad(h) <> ":" <> pad(mi) <> ":" <> pad(s)
  end

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: Integer.to_string(n)
end
