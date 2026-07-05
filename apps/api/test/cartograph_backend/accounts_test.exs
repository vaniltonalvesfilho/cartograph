defmodule CartographBackend.AccountsTest do
  # Locks the mass-assignment protection on the admin flag: the common
  # create/update paths must never grant admin, only the privileged variants.
  use CartographBackend.DataCase, async: true

  alias CartographBackend.Accounts

  @attrs %{"name" => "u", "email" => "u@ex.com", "password" => "secret123"}

  test "create_user ignores is_admin in attrs" do
    assert {:ok, user} = Accounts.create_user(Map.put(@attrs, "is_admin", true))
    refute user.is_admin
  end

  test "update_user ignores is_admin in attrs" do
    {:ok, user} = Accounts.create_user(@attrs)
    assert {:ok, user} = Accounts.update_user(user.id, %{"is_admin" => true})
    refute user.is_admin
  end

  test "admin_create_user applies is_admin" do
    assert {:ok, user} = Accounts.admin_create_user(Map.put(@attrs, "is_admin", true))
    assert user.is_admin
  end

  test "admin_update_user applies is_admin both ways" do
    {:ok, user} = Accounts.create_user(@attrs)
    assert {:ok, %{is_admin: true}} = Accounts.admin_update_user(user.id, %{"is_admin" => true})
    assert {:ok, %{is_admin: false}} = Accounts.admin_update_user(user.id, %{"is_admin" => false})
  end
end
