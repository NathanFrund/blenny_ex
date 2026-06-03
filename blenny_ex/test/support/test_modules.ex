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

defmodule BlennyTest.AuthTestModule do
  use Blenny.Module
  use GenServer

  @impl true
  def name, do: "auth-test"

  @impl true
  def capabilities, do: ["auth"]

  @impl true
  def routes do
    [
      {:get, "/auth/signin", :render_sign_in},
      {:post, "/auth/signin", :handle_sign_in},
      {:post, "/auth/avatar", :handle_avatar, [auth: true]}
    ]
  end

  @impl true
  def subscriptions, do: []

  @impl true
  def auth do
    [login_route: "/auth/signin"]
  end

  @impl true
  def child_spec(_opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}, restart: :permanent, type: :worker}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Blenny.AuthRegistry.register(%{
      module: __MODULE__,
      fetch_session: &BlennyTest.AuthTestModule.verify_request/1,
      login_route: "/auth/signin"
    })

    {:ok, %{}}
  end

  def verify_request(_conn) do
    %Blenny.Auth{id: "test-user", role: "user"}
  end
end

defmodule BlennyTest.RouterTestModule do
  use Blenny.Module

  @blenny_routes {:http, :get, "/public", __MODULE__, :public_action}
  @blenny_routes {:http, :get, "/also-public", __MODULE__, :also_public}
  @blenny_routes {:http, :post, "/protected", __MODULE__, :protected_action, [auth: true]}

  @impl true
  def name, do: "router-test"

  @impl true
  def routes, do: @blenny_routes

  @impl true
  def capabilities, do: []

  @impl true
  def subscriptions, do: []

  def init(_opts), do: {:ok, nil}
end
