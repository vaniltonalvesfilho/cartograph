defmodule CartographBackend.Vault do
  @aad "cartograph_ds_v1"

  def encrypt(plaintext) when is_binary(plaintext) do
    key = vault_key()
    iv = :crypto.strong_rand_bytes(12)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, true)
    iv <> tag <> ciphertext
  end

  def decrypt(nil), do: nil

  def decrypt(blob) when is_binary(blob) do
    key = vault_key()
    <<iv::binary-12, tag::binary-16, ciphertext::binary>> = blob
    :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false)
  end

  defp vault_key do
    base =
      Application.get_env(:cartograph_backend, CartographBackendWeb.Endpoint)[:secret_key_base] ||
        raise "secret_key_base not configured"
    :crypto.hash(:sha256, "vault_key_ds:" <> base)
  end
end
