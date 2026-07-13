defmodule Oneme.Billing.ProviderWebhook do
  @moduledoc "Verifies signatures for provider billing webhooks."

  @signature_header_prefix "sha256="

  def verify(provider, body, signature)
      when is_binary(provider) and is_binary(body) and is_binary(signature) do
    with {:ok, secret} <- secret_for(provider),
         expected <- signature(secret, body),
         true <- Plug.Crypto.secure_compare(expected, signature) do
      :ok
    else
      {:error, _reason} = error -> error
      false -> {:error, :invalid_signature}
    end
  end

  def verify(_provider, _body, _signature), do: {:error, :invalid_signature}

  def signature(secret, body) when is_binary(secret) and is_binary(body) do
    @signature_header_prefix <>
      (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))
  end

  defp secret_for(provider) do
    case secrets()[provider] do
      secret when is_binary(secret) and secret != "" -> {:ok, secret}
      _ -> {:error, :secret_not_configured}
    end
  end

  defp secrets do
    Application.get_env(:oneme, :billing_webhook_secrets) ||
      parse_secrets(System.get_env("ONEME_BILLING_WEBHOOK_SECRETS", ""))
  end

  defp parse_secrets(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.reduce(%{}, fn entry, acc ->
      case String.split(entry, "=", parts: 2) do
        [provider, secret] when provider != "" and secret != "" ->
          Map.put(acc, provider, secret)

        _ ->
          acc
      end
    end)
  end
end
