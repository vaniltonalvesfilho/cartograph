defmodule CartographBackend.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # The job data sandbox root is gitignored, so a fresh checkout won't have it.
    # Ensure it exists on boot so file-based features (Files view, readDirectory)
    # work without a manual mkdir. Write steps create their own subdirs on demand.
    File.mkdir_p!(CartographBackend.Steps.SafePath.root())

    children = [
      CartographBackendWeb.Telemetry,
      CartographBackend.Repo,
      {Task.Supervisor, name: CartographBackend.TaskSupervisor},
      {Phoenix.PubSub, name: CartographBackend.PubSub},
      {Cluster.Supervisor, [Application.get_env(:libcluster, :topologies, []), [name: CartographBackend.ClusterSupervisor]]},
      {Oban, Application.fetch_env!(:cartograph_backend, Oban)},
      CartographBackend.Engine.CronScheduler,
      CartographBackendWeb.Endpoint,
      {Absinthe.Subscription, CartographBackendWeb.Endpoint}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CartographBackend.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CartographBackendWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
