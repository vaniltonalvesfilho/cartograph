defmodule CartographBackendWeb.Router do
  use CartographBackendWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_auth do
    plug :accepts, ["json"]
    plug CartographBackendWeb.Plugs.AuthPlug
    plug CartographBackendWeb.Plugs.RequireAuth
  end

  pipeline :graphql do
    plug :accepts, ["json"]
    plug CartographBackendWeb.Plugs.AuthPlug
    plug CartographBackendWeb.Plugs.RequireAuth
    plug CartographBackendWeb.Plugs.AbsintheContext
  end

  # Public — login + 2FA verification
  scope "/api/auth", CartographBackendWeb do
    pipe_through :api
    post "/login", AuthController, :login
    post "/2fa/verify", AuthController, :verify_totp_login
  end

  # Requires auth — current user info + 2FA setup
  scope "/api/auth", CartographBackendWeb do
    pipe_through :require_auth
    get "/me", AuthController, :me
    get "/2fa/setup", AuthController, :totp_setup
    post "/2fa/enable", AuthController, :totp_enable
    delete "/2fa/disable", AuthController, :totp_disable
  end

  # All protected API routes
  scope "/api", CartographBackendWeb do
    pipe_through :require_auth

    # API tokens (personal)
    get "/tokens", ApiTokenController, :index
    post "/tokens", ApiTokenController, :create
    delete "/tokens/:id", ApiTokenController, :delete

    # User management (admin-only enforced in controller)
    get "/users/pickable", UserController, :pickable
    get "/users", UserController, :index
    post "/users", UserController, :create
    put "/users/:id", UserController, :update
    delete "/users/:id", UserController, :delete

    # Access levels (reference data for the member picker)
    get "/access-levels", MemberController, :levels

    # Group members
    get "/groups/:group_id/members", MemberController, :index_group
    post "/groups/:group_id/members", MemberController, :create_group
    delete "/groups/:group_id/members/:user_id", MemberController, :delete_group

    # Project members
    get "/projects/:project_id/members", MemberController, :index_project
    post "/projects/:project_id/members", MemberController, :create_project
    delete "/projects/:project_id/members/:user_id", MemberController, :delete_project

    # Task members
    get "/tasks/:task_id/members", MemberController, :index_task
    post "/tasks/:task_id/members", MemberController, :create_task
    delete "/tasks/:task_id/members/:user_id", MemberController, :delete_task

    # Tasks — /tasks/steps MUST come before /tasks/:id
    get "/tasks/steps", TaskController, :available_steps
    get "/tasks/graph", TaskController, :graph
    get "/tasks", TaskController, :index
    post "/tasks", TaskController, :create
    put "/tasks/:id", TaskController, :update
    delete "/tasks/:id", TaskController, :delete
    get "/tasks/:id/flow", TaskController, :flow
    post "/tasks/:id/run", TaskController, :run

    # Groups & Projects
    get "/groups", GroupController, :index
    post "/groups", GroupController, :create
    get "/groups/:id", GroupController, :show
    put "/groups/:id", GroupController, :update
    delete "/groups/:id", GroupController, :delete

    get "/projects", ProjectController, :index
    post "/projects", ProjectController, :create
    get "/projects/:id", ProjectController, :show
    put "/projects/:id", ProjectController, :update
    delete "/projects/:id", ProjectController, :delete

    # SMTP settings (admin-only enforced in controller)
    get "/smtp-settings", SmtpSettingController, :show
    put "/smtp-settings", SmtpSettingController, :update
    post "/smtp-settings/test", SmtpSettingController, :test

    # Data sources (admin CRUD)
    get "/data-sources", DataSourceController, :index
    post "/data-sources", DataSourceController, :create
    put "/data-sources/:id", DataSourceController, :update
    delete "/data-sources/:id", DataSourceController, :delete
    get "/data-sources/:id/health", DataSourceController, :health

    # Data sources per project
    get "/projects/:project_id/data-sources", DataSourceController, :index_for_project
    post "/projects/:project_id/data-sources/:data_source_id", DataSourceController, :assign
    delete "/projects/:project_id/data-sources/:data_source_id", DataSourceController, :unassign

    # Slack webhooks per project (write requires Navigator+, enforced in controller)
    get "/projects/:project_id/slack-webhooks", SlackWebhookController, :index
    post "/projects/:project_id/slack-webhooks", SlackWebhookController, :create
    put "/projects/:project_id/slack-webhooks/:id", SlackWebhookController, :update
    delete "/projects/:project_id/slack-webhooks/:id", SlackWebhookController, :delete

    # Files area over the job data sandbox (admin-only enforced in controller)
    get "/files", FileController, :index
    post "/files", FileController, :create
    post "/files/mkdir", FileController, :mkdir
    get "/files/download", FileController, :download
    delete "/files", FileController, :delete

    # Executions
    get "/executions", ExecutionController, :index
    get "/executions/:id", ExecutionController, :show
    post "/executions/:id/stop", ExecutionController, :stop

    # Logs — /logs/stream MUST come before /logs
    get "/executions/:id/logs/stream", LogController, :stream
    get "/executions/:id/logs", LogController, :history

    # System monitoring
    get "/system/metrics", SystemController, :metrics
    get "/system/health", SystemController, :health
  end

  scope "/" do
    pipe_through :graphql

    forward "/graphql", Absinthe.Plug, schema: CartographBackendWeb.Schema
  end

  if Application.compile_env(:cartograph_backend, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]
      live_dashboard "/dashboard", metrics: CartographBackendWeb.Telemetry
    end

    forward "/graphiql", Absinthe.Plug.GraphiQL,
      schema: CartographBackendWeb.Schema,
      socket: CartographBackendWeb.UserSocket
  end
end
