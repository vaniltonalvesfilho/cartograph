defmodule CartographBackend.Steps.ValidateStepTest do
  use ExUnit.Case, async: true

  alias CartographBackend.Engine.StepContext
  alias CartographBackend.Steps.ValidateStep

  defp ctx(params, state) do
    %StepContext{
      params: params,
      state: state,
      execution_id: 1,
      step_execution_id: 1,
      project_id: nil,
      log: fn _level, _msg -> :ok end,
      cancelled?: fn -> false end
    }
  end

  # ── Param handling ─────────────────────────────────────────────────────────────

  test "no params → error listing the available validators" do
    assert {:error, msg} = ValidateStep.execute(ctx(%{}, %{}))
    assert msg =~ "at least one of: cep, cnpj, cpf, email, regex, telefone"
  end

  test "unknown validator → error" do
    assert {:error, msg} = ValidateStep.execute(ctx(%{"rg" => "rows.rg"}, %{}))
    assert msg =~ "unknown validator 'rg'"
  end

  test "blank path (the DSL placeholder) → error asking for a field" do
    assert {:error, msg} = ValidateStep.execute(ctx(%{"email" => ""}, %{}))
    assert msg =~ "'email' needs a state field path"
  end

  # ── email ──────────────────────────────────────────────────────────────────────

  test "valid email in the state passes" do
    assert {:ok, _} =
             ValidateStep.execute(ctx(%{"email" => "contact"}, %{"contact" => "ana@ex.com"}))
  end

  test "invalid or missing email fails naming path and value" do
    assert {:error, msg} =
             ValidateStep.execute(ctx(%{"email" => "contact"}, %{"contact" => "ana@@ex"}))

    assert msg =~ ~s(email 'contact': "ana@@ex" is not a valid email)

    assert {:error, msg} = ValidateStep.execute(ctx(%{"email" => "contact"}, %{}))
    assert msg =~ ~s{email 'contact': "contact" is not a valid email (nor a state field)}
  end

  # ── Literal fallback ───────────────────────────────────────────────────────────

  test "a param matching no state field is validated as a literal" do
    assert {:ok, _} = ValidateStep.execute(ctx(%{"email" => "teste@example.com"}, %{}))
    assert {:ok, _} = ValidateStep.execute(ctx(%{"cpf" => "529.982.247-25"}, %{}))

    params = %{"regex" => "ABC-123", "pattern" => "^[A-Z]{3}-[0-9]+$"}
    assert {:ok, _} = ValidateStep.execute(ctx(params, %{}))

    assert {:error, msg} = ValidateStep.execute(ctx(%{"email" => "teste@@example"}, %{}))
    assert msg =~ "(nor a state field)"
  end

  test "a state field takes precedence over the literal reading" do
    # the field exists and holds garbage — must fail even though a literal
    # reading of the param would never match a field named like an email
    state = %{"contact" => "not-an-email"}
    assert {:error, msg} = ValidateStep.execute(ctx(%{"email" => "contact"}, state))
    assert msg =~ ~s("not-an-email" is not a valid email)
  end

  # ── cpf / cnpj (check digits) ──────────────────────────────────────────────────

  test "cpf accepts formatted and bare valid documents, rejects bad check digits" do
    for good <- ["529.982.247-25", "52998224725"] do
      assert {:ok, _} = ValidateStep.execute(ctx(%{"cpf" => "doc"}, %{"doc" => good})), good
    end

    for bad <- ["529.982.247-26", "11111111111", "5299822472", "abc", 52_998_224_725] do
      assert {:error, _} = ValidateStep.execute(ctx(%{"cpf" => "doc"}, %{"doc" => bad})),
             inspect(bad)
    end
  end

  test "cnpj accepts valid documents, rejects bad check digits and repeats" do
    for good <- ["11.222.333/0001-81", "11222333000181"] do
      assert {:ok, _} = ValidateStep.execute(ctx(%{"cnpj" => "doc"}, %{"doc" => good})), good
    end

    for bad <- ["11.222.333/0001-80", "00000000000000", "1122233300018"] do
      assert {:error, _} = ValidateStep.execute(ctx(%{"cnpj" => "doc"}, %{"doc" => bad})), bad
    end
  end

  test "cnpj accepts the alphanumeric format (check digits via ASCII − 48)" do
    # 12ABC34501DE35 computed independently: DV1 = 3, DV2 = 5
    for good <- ["12ABC34501DE35", "12.ABC.345/01DE-35", "12abc34501de35"] do
      assert {:ok, _} = ValidateStep.execute(ctx(%{"cnpj" => "doc"}, %{"doc" => good})), good
    end

    for bad <- ["12ABC34501DE36", "12ABC34501DEA5", "AAAAAAAAAAAAAA", "12ABC34501D"] do
      assert {:error, _} = ValidateStep.execute(ctx(%{"cnpj" => "doc"}, %{"doc" => bad})), bad
    end
  end

  # ── telefone / cep ─────────────────────────────────────────────────────────────

  test "telefone accepts mobile and landline formats, with or without +55" do
    for good <- [
          "(11) 91234-5678",
          "11912345678",
          "+55 11 91234-5678",
          "5511912345678",
          "(31) 3456-7890",
          "3134567890"
        ] do
      assert {:ok, _} = ValidateStep.execute(ctx(%{"telefone" => "tel"}, %{"tel" => good})), good
    end

    for bad <- ["119123", "01912345678", "11812345678", "1191234567890", "abc", ""] do
      assert {:error, _} = ValidateStep.execute(ctx(%{"telefone" => "tel"}, %{"tel" => bad})),
             inspect(bad)
    end
  end

  test "cep accepts 8 digits with optional hyphen" do
    for good <- ["01310-100", "01310100"] do
      assert {:ok, _} = ValidateStep.execute(ctx(%{"cep" => "cep"}, %{"cep" => good})), good
    end

    for bad <- ["1310-100", "013101000", "01310-10a", ""] do
      assert {:error, _} = ValidateStep.execute(ctx(%{"cep" => "cep"}, %{"cep" => bad})),
             inspect(bad)
    end
  end

  # ── regex ──────────────────────────────────────────────────────────────────────

  test "regex validates against the pattern param" do
    params = %{"regex" => "rows.sku", "pattern" => "^[A-Z]{3}-[0-9]+$"}
    rows_ok = [%{"sku" => "ABC-123"}, %{"sku" => "XYZ-9"}]
    assert {:ok, _} = ValidateStep.execute(ctx(params, %{"rows" => rows_ok}))

    assert {:error, msg} =
             ValidateStep.execute(ctx(params, %{"rows" => [%{"sku" => "abc-123"}]}))

    assert msg =~ ~s(regex 'rows.sku': "abc-123" does not match "^[A-Z]{3}-[0-9]+$")
  end

  test "regex config errors: missing pattern, orphan pattern, invalid pattern" do
    assert {:error, msg} = ValidateStep.execute(ctx(%{"regex" => "rows.sku"}, %{}))
    assert msg =~ "'regex' needs a 'pattern' param"

    assert {:error, msg} = ValidateStep.execute(ctx(%{"pattern" => "^a$", "email" => "e"}, %{}))
    assert msg =~ "'pattern' only makes sense together with 'regex'"

    assert {:error, msg} =
             ValidateStep.execute(ctx(%{"regex" => "rows.sku", "pattern" => "["}, %{}))

    assert msg =~ "invalid pattern"
  end

  # ── Dot paths and list fan-out ─────────────────────────────────────────────────

  test "dot path descends into nested maps" do
    state = %{"customer" => %{"contact" => %{"email" => "x@y.com"}}}
    assert {:ok, _} = ValidateStep.execute(ctx(%{"email" => "customer.contact.email"}, state))
  end

  test "a list fans out: every element is validated and all violations are reported" do
    rows = [
      %{"email" => "a@b.com"},
      %{"email" => "quebrado"},
      %{"email" => "c@d.com"},
      %{}
    ]

    assert {:error, msg} =
             ValidateStep.execute(ctx(%{"email" => "rows.email"}, %{"rows" => rows}))

    assert msg =~ "2 violation(s)"
  end

  test "multiple validators run together and pass" do
    state = %{
      "rows" => [%{"email" => "a@b.com", "cpf" => "529.982.247-25"}],
      "company" => %{"cnpj" => "11222333000181"}
    }

    params = %{"email" => "rows.email", "cpf" => "rows.cpf", "cnpj" => "company.cnpj"}
    assert {:ok, _} = ValidateStep.execute(ctx(params, state))
  end
end
