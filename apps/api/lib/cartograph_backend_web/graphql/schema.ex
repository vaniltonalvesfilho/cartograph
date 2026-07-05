defmodule CartographBackendWeb.Schema do
  use Absinthe.Schema

  alias CartographBackendWeb.Graphql.Resolvers
  alias CartographBackendWeb.Graphql.Authz
  alias CartographBackendWeb.Graphql.Middleware.RequireAuth

  # Fail-closed: every root field requires an authenticated user, regardless of
  # transport. Nested object fields inherit the gate from their root.
  def middleware(middleware, _field, %Absinthe.Type.Object{identifier: id})
      when id in [:query, :mutation, :subscription],
      do: [RequireAuth | middleware]

  def middleware(middleware, _field, _object), do: middleware

  # ── Scalar helpers ───────────────────────────────────────────────────────────

  scalar :datetime_string, description: "ISO8601 datetime as string" do
    serialize &to_iso8601/1
    parse fn
      %Absinthe.Blueprint.Input.String{value: v} -> {:ok, v}
      _ -> :error
    end
  end

  defp to_iso8601(nil), do: nil
  defp to_iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp to_iso8601(value), do: to_string(value)

  # ── Object types ─────────────────────────────────────────────────────────────

  object :group do
    field :id,          non_null(:id)
    field :name,        non_null(:string)
    field :description, :string
    field :parent_id,   :id
    field :position,    :integer
    field :created_at,  :datetime_string
  end

  object :project do
    field :id,          non_null(:id)
    field :name,        non_null(:string)
    field :description, :string
    field :group_id,    :id
    field :position,    :integer
    field :created_at,  :datetime_string
  end

  object :task_definition do
    field :id,          non_null(:id)
    field :name,        non_null(:string)
    field :identifier,  :string
    field :code,        :string
    field :description, :string
    field :dsl,         non_null(:string)
    field :cron,        :string
    field :project_id,  :id
    field :release_at,  :datetime_string
    field :archive_at,  :datetime_string
    field :created_at,  :datetime_string
  end

  object :task_execution do
    field :id,                  non_null(:id)
    field :task_definition_id,  :id
    field :task_name,           :string
    field :status,              :string
    field :trigger,             :string
    field :created_at,          :datetime_string
    field :started_at,          :datetime_string
    field :finished_at,         :datetime_string
  end

  object :step_execution do
    field :id,            non_null(:id)
    field :execution_id,  :id
    field :step_name,     :string
    field :step_order,    :integer
    field :status,        :string
    field :started_at,    :datetime_string
    field :finished_at,   :datetime_string
    field :error_message, :string
    field :flow_node_id,  :string
  end

  object :execution_log do
    field :id,                non_null(:id)
    field :execution_id,      :id
    field :step_execution_id, :id
    field :level,             :string
    field :message,           :string
    field :timestamp,         :datetime_string
  end

  object :dashboard_metrics do
    field :total_tasks,    :integer
    field :total_groups,   :integer
    field :total_projects, :integer
    field :running,        :integer
    field :scheduled,      :integer
    field :success_rate,   :float
  end

  object :run_result do
    field :execution_id, non_null(:id)
  end

  # ── Queries ──────────────────────────────────────────────────────────────────

  query do
    @desc "List all groups"
    field :groups, list_of(:group) do
      resolve &Resolvers.Groups.list/3
    end

    field :group, :group do
      arg :id, non_null(:id)
      resolve &Resolvers.Groups.get/3
    end

    @desc "List projects, optionally filtered by group"
    field :projects, list_of(:project) do
      arg :group_id, :id
      resolve &Resolvers.Projects.list/3
    end

    field :project, :project do
      arg :id, non_null(:id)
      resolve &Resolvers.Projects.get/3
    end

    @desc "List tasks, optionally filtered by project"
    field :tasks, list_of(:task_definition) do
      arg :project_id, :id
      resolve &Resolvers.Tasks.list/3
    end

    field :task, :task_definition do
      arg :id, non_null(:id)
      resolve &Resolvers.Tasks.get/3
    end

    @desc "List executions, optionally filtered by task"
    field :executions, list_of(:task_execution) do
      arg :task_id, :id
      arg :limit,   :integer
      resolve &Resolvers.Executions.list/3
    end

    field :execution, :task_execution do
      arg :id, non_null(:id)
      resolve &Resolvers.Executions.get/3
    end

    field :execution_steps, list_of(:step_execution) do
      arg :execution_id, non_null(:id)
      resolve &Resolvers.Executions.list_steps/3
    end

    field :execution_logs, list_of(:execution_log) do
      arg :execution_id, non_null(:id)
      resolve &Resolvers.Executions.list_logs/3
    end

    field :dashboard_metrics, :dashboard_metrics do
      resolve &Resolvers.Metrics.dashboard/3
    end
  end

  # ── Mutations ─────────────────────────────────────────────────────────────────

  mutation do
    # Groups
    field :create_group, :group do
      arg :name,      non_null(:string)
      arg :parent_id, :id
      resolve &Resolvers.Groups.create/3
    end

    field :update_group, :group do
      arg :id,        non_null(:id)
      arg :name,      :string
      arg :parent_id, :id
      resolve &Resolvers.Groups.update/3
    end

    field :delete_group, :boolean do
      arg :id, non_null(:id)
      resolve &Resolvers.Groups.delete/3
    end

    # Projects
    field :create_project, :project do
      arg :name,     non_null(:string)
      arg :group_id, :id
      resolve &Resolvers.Projects.create/3
    end

    field :update_project, :project do
      arg :id,       non_null(:id)
      arg :name,     :string
      arg :group_id, :id
      resolve &Resolvers.Projects.update/3
    end

    field :delete_project, :boolean do
      arg :id, non_null(:id)
      resolve &Resolvers.Projects.delete/3
    end

    # Tasks
    field :create_task, :task_definition do
      arg :name,       non_null(:string)
      arg :identifier, non_null(:string)
      arg :dsl,        non_null(:string)
      arg :cron,       :string
      arg :project_id, :id
      arg :release_at, :datetime_string
      arg :archive_at, :datetime_string
      resolve &Resolvers.Tasks.create/3
    end

    field :update_task, :task_definition do
      arg :id,         non_null(:id)
      arg :name,       :string
      arg :dsl,        :string
      arg :cron,       :string
      arg :project_id, :id
      arg :release_at, :datetime_string
      arg :archive_at, :datetime_string
      resolve &Resolvers.Tasks.update/3
    end

    field :delete_task, :boolean do
      arg :id, non_null(:id)
      resolve &Resolvers.Tasks.delete/3
    end

    field :run_task, :run_result do
      arg :id, non_null(:id)
      resolve &Resolvers.Tasks.run/3
    end

    field :stop_execution, :task_execution do
      arg :id, non_null(:id)
      resolve &Resolvers.Executions.stop/3
    end
  end

  # ── Subscriptions ─────────────────────────────────────────────────────────────

  subscription do
    @desc "Receives real-time logs of an execution"
    field :execution_log, :execution_log do
      arg :execution_id, non_null(:id)

      config fn args, %{context: ctx} ->
        case Authz.authorize_execution_id(ctx[:current_user], :view, args.execution_id) do
          :ok -> {:ok, topic: "execution:#{args.execution_id}"}
          error -> error
        end
      end
    end

    @desc "Receives status updates of an execution"
    field :execution_status, :task_execution do
      arg :execution_id, non_null(:id)

      config fn args, %{context: ctx} ->
        case Authz.authorize_execution_id(ctx[:current_user], :view, args.execution_id) do
          :ok -> {:ok, topic: "execution_status:#{args.execution_id}"}
          error -> error
        end
      end
    end

    @desc "Receives the execution status of a job (to color graphs without polling)"
    field :task_execution_updated, :task_execution do
      arg :task_id, non_null(:id)

      config fn args, %{context: ctx} ->
        case Authz.authorize_task_id(ctx[:current_user], :view, args.task_id) do
          :ok -> {:ok, topic: "task_executions:#{args.task_id}"}
          error -> error
        end
      end
    end

    @desc "Receives each status transition of an execution's steps"
    field :step_updated, :step_execution do
      arg :execution_id, non_null(:id)

      config fn args, %{context: ctx} ->
        case Authz.authorize_execution_id(ctx[:current_user], :view, args.execution_id) do
          :ok -> {:ok, topic: "execution_steps:#{args.execution_id}"}
          error -> error
        end
      end
    end
  end
end
