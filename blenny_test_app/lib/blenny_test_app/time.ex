defmodule BlennyTestApp.Time do
  @moduledoc false

  def timezone do
    Application.get_env(:blenny_test_app, :timezone, "Etc/UTC")
  end

  def now do
    DateTime.now!(timezone())
  end

  def format_timestamp do
    now() |> Calendar.strftime("%H:%M:%S")
  end

  def from_unix_ms(ts) when is_integer(ts) do
    ts
    |> div(1000)
    |> DateTime.from_unix!()
    |> DateTime.shift_zone!(timezone())
    |> Calendar.strftime("%H:%M:%S")
  end
end
