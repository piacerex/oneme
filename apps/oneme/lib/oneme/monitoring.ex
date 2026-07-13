defmodule Oneme.Monitoring do
  @moduledoc "Configured CDN endpoint health checks."

  def check_cdn do
    urls = configured_urls()

    cond do
      urls == [] ->
        %{status: "not_configured", checkedAt: DateTime.utc_now(), endpoints: []}

      true ->
        endpoints = Enum.map(urls, &check_url/1)
        status = if Enum.all?(endpoints, & &1.ok), do: "ok", else: "degraded"
        %{status: status, checkedAt: DateTime.utc_now(), endpoints: endpoints}
    end
  end

  defp configured_urls do
    System.get_env("ONEME_CDN_URLS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp check_url(url) do
    started_at = System.monotonic_time(:millisecond)

    case validate_url(url) do
      :ok ->
        result = request_head(url)
        response_ms = System.monotonic_time(:millisecond) - started_at

        Map.merge(result, %{url: url, responseMs: response_ms})

      {:error, reason} ->
        %{url: url, ok: false, status: nil, responseMs: 0, error: reason}
    end
  end

  defp validate_url(url) do
    uri = URI.parse(url)
    allowed_hosts = allowed_hosts()

    cond do
      uri.scheme != "https" ->
        {:error, "cdn endpoint must use https"}

      is_nil(uri.host) ->
        {:error, "cdn endpoint host is missing"}

      allowed_hosts != [] and uri.host not in allowed_hosts ->
        {:error, "cdn endpoint host is not allowed"}

      true ->
        :ok
    end
  end

  defp allowed_hosts do
    System.get_env("ONEME_CDN_ALLOWED_HOSTS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp request_head(url) do
    case :httpc.request(
           :head,
           {String.to_charlist(url), []},
           [timeout: 5_000, connect_timeout: 2_000],
           []
         ) do
      {:ok, {{_version, status, _reason}, _headers, _body}} when status in 200..399 ->
        %{ok: true, status: status, error: nil}

      {:ok, {{_version, status, _reason}, _headers, _body}} ->
        %{ok: false, status: status, error: "cdn returned HTTP #{status}"}

      {:error, reason} ->
        %{ok: false, status: nil, error: "cdn request failed: #{inspect(reason)}"}
    end
  rescue
    error -> %{ok: false, status: nil, error: "cdn request failed: #{Exception.message(error)}"}
  end
end
