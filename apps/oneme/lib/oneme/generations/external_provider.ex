defmodule Oneme.Generations.ExternalProvider do
  @moduledoc "HTTP JSON adapter for image-aware generation providers."

  @timeout 30_000
  @blocked_keys ~w(faceImageDataUrl facePhotoDataUrl imageDataUrl imageData rawImage photo)

  def generate(input_config) when is_map(input_config) do
    case provider_url() do
      nil ->
        {:error, :not_configured}

      url ->
        Application.ensure_all_started(:inets)
        Application.ensure_all_started(:ssl)
        request(url, sanitize(input_config))
    end
  end

  defp request(url, input_config) do
    headers =
      [{~c"content-type", ~c"application/json"}]
      |> maybe_authorization()

    body =
      Jason.encode!(%{
        "kind" => "face_candidates",
        "avatarConfig" => input_config
      })

    case :httpc.request(
           :post,
           {String.to_charlist(url), headers, ~c"application/json", body},
           [timeout: @timeout, connect_timeout: 5_000],
           body_format: :binary
         ) do
      {:ok, {{_version, status, _reason}, _response_headers, response_body}}
      when status in 200..299 ->
        decode_response(response_body)

      {:ok, {{_version, status, _reason}, _response_headers, response_body}} ->
        {:error, :provider_http_error,
         "provider responded with HTTP #{status}: #{truncate(response_body)}"}

      {:error, reason} ->
        {:error, :provider_request_failed, inspect(reason)}
    end
  rescue
    error -> {:error, :provider_request_failed, Exception.message(error)}
  end

  defp decode_response(response_body) do
    with {:ok, payload} <- Jason.decode(response_body),
         candidates when is_list(candidates) <- Map.get(payload, "candidates"),
         true <- candidates != [] do
      {:ok,
       %{
         provider: Map.get(payload, "provider", "external_http"),
         candidates: Enum.take(candidates, 3)
       }}
    else
      {:error, %Jason.DecodeError{}} ->
        {:error, :provider_invalid_json, "provider returned invalid JSON"}

      nil ->
        {:error, :provider_invalid_response, "provider response has no candidates list"}

      false ->
        {:error, :provider_invalid_response, "provider returned no candidates"}

      _ ->
        {:error, :provider_invalid_response, "provider response is not an object"}
    end
  end

  defp provider_url do
    case System.get_env("ONEME_GENERATION_PROVIDER_URL") do
      url when is_binary(url) and url != "" ->
        if valid_url?(url), do: url, else: nil

      _ ->
        nil
    end
  end

  defp valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) -> true
      %URI{scheme: "http", host: host} when is_binary(host) -> insecure_http_allowed?(host)
      _ -> false
    end
  end

  defp insecure_http_allowed?(host) do
    host in ["localhost", "127.0.0.1"] and
      System.get_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP", "false") in ["1", "true"]
  end

  defp maybe_authorization(headers) do
    case System.get_env("ONEME_GENERATION_PROVIDER_API_KEY") do
      key when is_binary(key) and key != "" ->
        headers ++ [{~c"authorization", String.to_charlist("Bearer " <> key)}]

      _ ->
        headers
    end
  end

  defp truncate(value) when is_binary(value), do: String.slice(value, 0, 500)
  defp truncate(value), do: inspect(value) |> String.slice(0, 500)

  defp sanitize(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested}, acc ->
      if to_string(key) in @blocked_keys do
        acc
      else
        Map.put(acc, key, sanitize(nested))
      end
    end)
  end

  defp sanitize(value) when is_list(value), do: Enum.map(value, &sanitize/1)
  defp sanitize(value), do: value
end
