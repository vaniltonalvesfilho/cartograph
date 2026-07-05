defmodule CartographBackend.Mailer do
  @moduledoc """
  Swoosh mailer. The SMTP relay configuration is supplied at delivery time from
  the database (see `CartographBackend.Mailing`), not from compile-time config.
  """
  use Swoosh.Mailer, otp_app: :cartograph_backend
end
