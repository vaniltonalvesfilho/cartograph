# Seed: data sources + sample jobs for testing DB & XML/JSON steps.
# Run with: mix run priv/repo/seeds_datasources.exs

alias CartographBackend.{DataSources, Groups, Tasks, Accounts}

# ── Ensure demo group + project ───────────────────────────────────────────────

demo_group =
  case Groups.list_groups() |> Enum.find(&(&1.name == "Demo")) do
    nil ->
      {:ok, g} = Groups.create_group(%{"name" => "Demo", "description" => "Demonstration group"})
      IO.puts("Group 'Demo' created")
      g
    g ->
      IO.puts("Group 'Demo' already exists")
      g
  end

demo_project =
  case Groups.list_projects() |> Enum.find(&(&1.name == "MySQL Integration")) do
    nil ->
      {:ok, p} = Groups.create_project(%{
        "name"        => "MySQL Integration",
        "description" => "Demo project for MySQL database integration",
        "group_id"    => demo_group.id
      })
      IO.puts("Project 'MySQL Integration' created (id=#{p.id})")
      p
    p ->
      IO.puts("Project already exists (id=#{p.id})")
      p
  end

# ── Data source: MySQL local ───────────────────────────────────────────────────

mysql_ds =
  case DataSources.get_by_slug("mysql-local") do
    {:ok, ds} ->
      IO.puts("DataSource 'mysql-local' already exists (id=#{ds.id})")
      ds
    {:error, :not_found} ->
      {:ok, ds} = DataSources.create(%{
        "name"          => "MySQL Local (Demo)",
        "slug"          => "mysql-local",
        "adapter"       => "mysql",
        "host"          => "localhost",
        "port"          => 3306,
        "database_name" => "cartograph_demo",
        "username"      => "cartograph",
        "password"      => "cartograph2026",
        "ssl"           => false,
        "notes"         => "Demo data source — requires a local MySQL on port 3306 (db cartograph_demo)"
      })
      IO.puts("DataSource 'mysql-local' created (id=#{ds.id})")
      ds
  end

# Assign to demo project
:ok = DataSources.assign_to_project(mysql_ds.id, demo_project.id)
IO.puts("DataSource #{mysql_ds.slug} → project #{demo_project.name}")

# ── Job 1: Export MySQL products to XML ───────────────────────────────────────

export_dsl = """
exportProductsXml {
  step "queryDatabase" {
    source "mysql-local"
    query "SELECT id, name, category, price, stock FROM products WHERE active = 1 ORDER BY name"
    result_key "products"
  },
  step "writeXml" {
    data_key "products"
    path "data/output/products_export.xml"
    root_element "catalog"
    row_element "product"
  },
}
"""

case Tasks.list_tasks() |> Enum.find(&(&1.name == "Export Products → XML")) do
  nil ->
    {:ok, t} = Tasks.create_task(%{
      "name"       => "Export Products → XML",
      "identifier" => "export-products-xml",
      "description" => "Queries active products in MySQL and exports them to data/output/products_export.xml",
      "project_id" => demo_project.id,
      "dsl"        => export_dsl
    }, :system)
    IO.puts("Job 'Export Products → XML' created (id=#{t.id}, code=#{t.code})")
  t ->
    IO.puts("Job already exists (id=#{t.id})")
end

# ── Job 2: Import XML catalog into MySQL ──────────────────────────────────────

import_dsl = """
importCatalogXmlMysql {
  step "parseXml" {
    path "data/sample/catalog.xml"
    root_element "product"
    result_key "items"
  },
  step "executeDatabase" {
    source "mysql-local"
    query "INSERT INTO imported_items (name, category, price) VALUES (?, ?, ?)"
    rows_from "items"
    columns "name,category,price"
  },
}
"""

case Tasks.list_tasks() |> Enum.find(&(&1.name == "Import Catalog XML → MySQL")) do
  nil ->
    {:ok, t} = Tasks.create_task(%{
      "name"        => "Import Catalog XML → MySQL",
      "identifier"  => "import-catalog-xml-mysql",
      "description" => "Reads data/sample/catalog.xml and inserts the products into MySQL's imported_items table",
      "project_id"  => demo_project.id,
      "dsl"         => import_dsl
    }, :system)
    IO.puts("Job 'Import Catalog XML → MySQL' created (id=#{t.id}, code=#{t.code})")
  t ->
    IO.puts("Job already exists (id=#{t.id})")
end

# ── Job 3: Export MySQL products to JSON ──────────────────────────────────────

export_json_dsl = """
exportProductsJson {
  step "queryDatabase" {
    source "mysql-local"
    query "SELECT id, name, category, price, stock FROM products WHERE active = 1 ORDER BY category, name"
    result_key "products"
  },
  step "writeJson" {
    data_key "products"
    path "data/output/products_export.json"
    pretty true
  },
}
"""

case Tasks.list_tasks() |> Enum.find(&(&1.name == "Export Products → JSON")) do
  nil ->
    {:ok, t} = Tasks.create_task(%{
      "name"        => "Export Products → JSON",
      "identifier"  => "export-products-json",
      "description" => "Queries active products in MySQL and exports them to data/output/products_export.json",
      "project_id"  => demo_project.id,
      "dsl"         => export_json_dsl
    }, :system)
    IO.puts("Job 'Export Products → JSON' created (id=#{t.id}, code=#{t.code})")
  t ->
    IO.puts("Job already exists (id=#{t.id})")
end

# ── Job 4: Import JSON catalog into MySQL ─────────────────────────────────────

import_json_dsl = """
importCatalogJsonMysql {
  step "parseJson" {
    path "data/sample/catalog.json"
    root_path "catalog.items"
    result_key "items"
  },
  step "executeDatabase" {
    source "mysql-local"
    query "INSERT INTO imported_items (name, category, price) VALUES (?, ?, ?)"
    rows_from "items"
    columns "name,category,price"
  },
}
"""

case Tasks.list_tasks() |> Enum.find(&(&1.name == "Import Catalog JSON → MySQL")) do
  nil ->
    {:ok, t} = Tasks.create_task(%{
      "name"        => "Import Catalog JSON → MySQL",
      "identifier"  => "import-catalog-json-mysql",
      "description" => "Reads data/sample/catalog.json (path catalog.items) and inserts into MySQL's imported_items table",
      "project_id"  => demo_project.id,
      "dsl"         => import_json_dsl
    }, :system)
    IO.puts("Job 'Import Catalog JSON → MySQL' created (id=#{t.id}, code=#{t.code})")
  t ->
    IO.puts("Job already exists (id=#{t.id})")
end

IO.puts("""

Done! Note: the demo jobs expect a local MySQL on port 3306 with database
`cartograph_demo` (user `cartograph`), containing the tables `products` and
`imported_items`, plus sample catalog files under data/sample/.
""")
