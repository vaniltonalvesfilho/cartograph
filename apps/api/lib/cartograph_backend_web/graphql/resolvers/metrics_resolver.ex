defmodule CartographBackendWeb.Graphql.Resolvers.Metrics do
  alias CartographBackend.Metrics

  def dashboard(_parent, _args, _res) do
    {:ok, Metrics.dashboard_metrics()}
  end
end
