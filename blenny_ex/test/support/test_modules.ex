defmodule BlennyTest.ModuleDeclarative do
  use Blenny.Module

  @impl true
  def name, do: "declarative"

  @impl true
  def routes, do: []

  @impl true
  def capabilities, do: []

  @impl true
  def subscriptions, do: []
end

defmodule BlennyTest.ModuleStateful do
  use Blenny.Module
  use GenServer

  @impl true
  def name, do: "stateful"

  @impl true
  def routes, do: []

  @impl true
  def capabilities, do: []

  @impl true
  def subscriptions, do: []

  @impl true
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      restart: :permanent,
      type: :worker
    }
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {Blenny.ModuleRegistry, {:global, __MODULE__}}}
    )
  end

  @impl true
  def init(_opts), do: {:ok, %{}}
end

defmodule BlennyTest.ModuleWithCapability do
  use Blenny.Module

  @impl true
  def name, do: "capable"

  @impl true
  def routes, do: []

  @impl true
  def capabilities, do: ["auth"]

  @impl true
  def subscriptions, do: []
end
