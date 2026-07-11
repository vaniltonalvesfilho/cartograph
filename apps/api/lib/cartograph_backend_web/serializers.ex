defmodule CartographBackendWeb.Serializers do
  @moduledoc "Converts Ecto schemas to camelCase maps for the API responses."

  alias CartographBackend.Authorization

  # Merges accessLevel + can flags from a precomputed level (avoids re-querying
  # in list endpoints that already have the user's scope).
  defp access(level), do: %{accessLevel: level, can: Authorization.can_from_level(level)}

  def task_definition(t) do
    %{
      id: t.id,
      name: t.name,
      identifier: t.identifier,
      code: t.code,
      description: t.description,
      dsl: t.dsl,
      cron: t.cron,
      agentTokenBudget: t.agent_token_budget,
      projectId: t.project_id,
      releaseAt: t.release_at,
      archiveAt: t.archive_at,
      createdAt: t.created_at,
      updatedAt: t.updated_at
    }
  end

  def task_definition(t, level) when is_integer(level),
    do: Map.merge(task_definition(t), access(level))

  def task_execution(e) do
    %{
      id: e.id,
      taskDefinitionId: e.task_definition_id,
      taskName: e.task_name,
      status: e.status,
      trigger: e.trigger,
      createdAt: e.created_at,
      startedAt: e.started_at,
      finishedAt: e.finished_at
    }
  end

  def step_execution(s) do
    %{
      id: s.id,
      executionId: s.execution_id,
      stepName: s.step_name,
      stepOrder: s.step_order,
      status: s.status,
      startedAt: s.started_at,
      finishedAt: s.finished_at,
      errorMessage: s.error_message,
      flowNodeId: s.flow_node_id,
      agentUsage: agent_usage(s)
    }
  end

  @doc """
  Token usage of an `agent` step, or nil for every other step. Stored already
  camelCased under the step's generic `metadata` column.
  """
  def agent_usage(%{metadata: metadata}) when is_map(metadata), do: Map.get(metadata, "agent")
  def agent_usage(_), do: nil

  def execution_log(l) do
    %{
      id: l.id,
      executionId: l.execution_id,
      stepExecutionId: l.step_execution_id,
      level: l.level,
      message: l.message,
      timestamp: l.timestamp
    }
  end

  def group(g) do
    %{
      id: g.id,
      name: g.name,
      description: g.description,
      parentId: g.parent_id,
      position: g.position,
      createdAt: g.created_at,
      updatedAt: g.updated_at
    }
  end

  def group(g, level) when is_integer(level), do: Map.merge(group(g), access(level))

  def user(u) do
    %{
      id: u.id,
      name: u.name,
      email: u.email,
      isAdmin: u.is_admin,
      totpEnabled: u.totp_enabled,
      insertedAt: u.inserted_at
    }
  end

  def membership(m) do
    %{
      id: m.id,
      userId: m.user_id,
      subjectType: m.subject_type,
      subjectId: m.subject_id,
      accessLevel: m.access_level,
      levelName: CartographBackend.Authorization.level_name(m.access_level),
      user: if(Ecto.assoc_loaded?(m.user) && m.user != nil, do: user(m.user), else: nil)
    }
  end

  def project(p) do
    %{
      id: p.id,
      name: p.name,
      description: p.description,
      groupId: p.group_id,
      position: p.position,
      createdAt: p.created_at,
      updatedAt: p.updated_at
    }
  end

  def project(p, level) when is_integer(level), do: Map.merge(project(p), access(level))

  def data_source(ds) do
    %{
      id: ds.id,
      name: ds.name,
      slug: ds.slug,
      adapter: ds.adapter,
      host: ds.host,
      port: ds.port,
      databaseName: ds.database_name,
      username: ds.username,
      ssl: ds.ssl,
      notes: ds.notes,
      projectIds: Enum.map(ds.projects || [], & &1.id),
      insertedAt: ds.inserted_at,
      updatedAt: ds.updated_at
    }
  end

  def data_source(ds, :admin) do
    Map.put(data_source(ds), :can, %{edit: true, delete: true})
  end

  @doc """
  Slack webhook registered on a project. The URL is the secret and is NEVER
  returned — the DSL only needs the public `code`.
  """
  def slack_webhook(w) do
    %{
      id: w.id,
      name: w.name,
      code: w.code,
      projectId: w.project_id,
      insertedAt: w.inserted_at,
      updatedAt: w.updated_at
    }
  end

  @doc """
  Anthropic credential registered on a project. The API key is the secret and
  is NEVER returned — not even masked — the DSL only needs the public `code`.
  """
  def anthropic_credential(c) do
    %{
      id: c.id,
      name: c.name,
      code: c.code,
      projectId: c.project_id,
      insertedAt: c.inserted_at,
      updatedAt: c.updated_at
    }
  end

  @doc """
  SMTP settings for the admin dashboard. The password is NEVER returned — only
  a `passwordSet` flag indicating whether one is stored. Returns sensible empty
  defaults when no settings exist yet.
  """
  def smtp_settings(nil) do
    %{
      host: "",
      port: 587,
      username: "",
      fromName: "",
      fromEmail: "",
      tls: "if_available",
      auth: true,
      enabled: false,
      passwordSet: false
    }
  end

  def smtp_settings(s) do
    %{
      host: s.host,
      port: s.port,
      username: s.username,
      fromName: s.from_name,
      fromEmail: s.from_email,
      tls: s.tls,
      auth: s.auth,
      enabled: s.enabled,
      passwordSet: not is_nil(s.password_encrypted),
      updatedAt: s.updated_at
    }
  end
end
