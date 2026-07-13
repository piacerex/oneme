defmodule Oneme.Monitoring do
  @moduledoc "Configured CDN health checks, SLO probe evaluation, and alert delivery."

  def check_cdn do
    urls = configured_urls()

    cond do
      urls == [] ->
        enrich_report(%{status: "not_configured", checkedAt: DateTime.utc_now(), endpoints: []})

      true ->
        endpoints = Enum.map(urls, &check_url/1)
        status = if Enum.all?(endpoints, & &1.ok), do: "ok", else: "degraded"
        enrich_report(%{status: status, checkedAt: DateTime.utc_now(), endpoints: endpoints})
    end
  end

  def notify(report) when is_map(report) do
    with {:ok, url, secret} <- notification_config(),
         :ok <- validate_notification_url(url),
         body <- Jason.encode!(%{event: "oneme.monitoring", report: report}),
         signature <- sign(secret, body),
         {:ok, _status} <- post_notification(url, body, signature) do
      :ok
    end
  end

  defp configured_urls do
    System.get_env("ONEME_CDN_URLS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp enrich_report(%{status: "not_configured"} = report) do
    Map.put(report, :slo, slo_summary([]))
  end

  defp enrich_report(report) do
    alerts =
      report.endpoints
      |> Enum.flat_map(fn endpoint -> endpoint_alerts(endpoint) end)

    status = if alerts == [], do: report.status, else: "degraded"

    report
    |> Map.put(:status, status)
    |> Map.put(:alerts, alerts)
    |> Map.put(:slo, slo_summary(report.endpoints))
  end

  defp endpoint_alerts(%{ok: false} = endpoint) do
    [%{code: "cdn_endpoint_unhealthy", severity: "critical", url: endpoint.url}]
  end

  defp endpoint_alerts(endpoint) do
    if endpoint.responseMs > max_response_ms() do
      [
        %{
          code: "cdn_endpoint_slow",
          severity: "warning",
          url: endpoint.url,
          responseMs: endpoint.responseMs,
          thresholdMs: max_response_ms()
        }
      ]
    else
      []
    end
  end

  defp slo_summary([]) do
    %{
      window: "current_probe",
      availabilityTargetPercent: availability_target_percent(),
      probeAvailabilityPercent: nil,
      maxResponseMs: max_response_ms()
    }
  end

  defp slo_summary(endpoints) do
    available = Enum.count(endpoints, & &1.ok)

    %{
      window: "current_probe",
      availabilityTargetPercent: availability_target_percent(),
      probeAvailabilityPercent: Float.round(available / length(endpoints) * 100, 2),
      maxResponseMs: max_response_ms()
    }
  end

  defp availability_target_percent do
    case Float.parse(System.get_env("ONEME_CDN_SLO_AVAILABILITY_PERCENT", "99.9")) do
      {value, ""} when value >= 0 and value <= 100 -> value
      _ -> 99.9
    end
  end

  defp max_response_ms do
    case Integer.parse(System.get_env("ONEME_CDN_SLO_MAX_RESPONSE_MS", "1000")) do
      {value, ""} when value > 0 -> value
      _ -> 1000
    end
  end

  defp notification_config do
    case {System.get_env("ONEME_MONITORING_ALERT_URL"),
          System.get_env("ONEME_MONITORING_ALERT_SECRET")} do
      {url, secret} when is_binary(url) and url != "" and is_binary(secret) and secret != "" ->
        {:ok, url, secret}

      {nil, _} ->
        {:error, :not_configured}

      {_, nil} ->
        {:error, :secret_not_configured}

      _ ->
        {:error, :secret_not_configured}
    end
  end

  defp validate_notification_url(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) -> :ok
      _ -> {:error, :notification_url_must_use_https}
    end
  end

  defp sign(secret, body) do
    "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))
  end

  defp post_notification(url, body, signature) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    headers = [
      {~c"content-type", ~c"application/json"},
      {~c"x-oneme-monitoring-signature", String.to_charlist(signature)}
    ]

    case :httpc.request(
           :post,
           {String.to_charlist(url), headers, ~c"application/json", body},
           [timeout: 5_000, connect_timeout: 2_000],
           body_format: :binary
         ) do
      {:ok, {{_version, status, _reason}, _headers, _response_body}} when status in 200..299 ->
        {:ok, status}

      {:ok, {{_version, status, _reason}, _headers, _response_body}} ->
        {:error, {:notification_failed, status}}

      {:error, reason} ->
        {:error, {:notification_failed, reason}}
    end
  rescue
    error -> {:error, {:notification_failed, Exception.message(error)}}
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
