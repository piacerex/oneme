defmodule Oneme.MonitoringTest do
  use ExUnit.Case

  alias Oneme.Monitoring

  test "returns not configured when no CDN endpoints are set" do
    previous = System.get_env("ONEME_CDN_URLS")
    System.delete_env("ONEME_CDN_URLS")

    on_exit(fn -> restore_env("ONEME_CDN_URLS", previous) end)

    assert %{status: "not_configured", endpoints: [], slo: slo} = Monitoring.check_cdn()
    assert slo.window == "current_probe"
    assert slo.probeAvailabilityPercent == nil
  end

  test "rejects non-HTTPS and disallowed CDN endpoints without making a request" do
    previous_urls = System.get_env("ONEME_CDN_URLS")
    previous_hosts = System.get_env("ONEME_CDN_ALLOWED_HOSTS")
    System.put_env("ONEME_CDN_URLS", "http://localhost,https://cdn.example.com")
    System.put_env("ONEME_CDN_ALLOWED_HOSTS", "assets.example.com")

    on_exit(fn ->
      restore_env("ONEME_CDN_URLS", previous_urls)
      restore_env("ONEME_CDN_ALLOWED_HOSTS", previous_hosts)
    end)

    report = Monitoring.check_cdn()
    assert report.status == "degraded"
    assert Enum.all?(report.endpoints, &(&1.ok == false))
    assert Enum.all?(report.alerts, &(&1.code == "cdn_endpoint_unhealthy"))
    assert report.slo.probeAvailabilityPercent == 0.0
  end

  test "does not send monitoring notifications without explicit configuration" do
    previous_url = System.get_env("ONEME_MONITORING_ALERT_URL")
    previous_secret = System.get_env("ONEME_MONITORING_ALERT_SECRET")
    System.delete_env("ONEME_MONITORING_ALERT_URL")
    System.delete_env("ONEME_MONITORING_ALERT_SECRET")

    on_exit(fn ->
      restore_env("ONEME_MONITORING_ALERT_URL", previous_url)
      restore_env("ONEME_MONITORING_ALERT_SECRET", previous_secret)
    end)

    assert {:error, :not_configured} = Monitoring.notify(%{status: "ok"})
  end

  test "retries notifications with a stable event idempotency key" do
    {server, port} = start_retry_notification_server()
    previous_url = System.get_env("ONEME_MONITORING_ALERT_URL")
    previous_secret = System.get_env("ONEME_MONITORING_ALERT_SECRET")
    previous_http = System.get_env("ONEME_MONITORING_ALLOW_INSECURE_HTTP")
    previous_attempts = System.get_env("ONEME_MONITORING_NOTIFY_MAX_ATTEMPTS")
    previous_delay = System.get_env("ONEME_MONITORING_NOTIFY_RETRY_DELAY_MS")
    System.put_env("ONEME_MONITORING_ALERT_URL", "http://127.0.0.1:#{port}")
    System.put_env("ONEME_MONITORING_ALERT_SECRET", "monitoring-secret")
    System.put_env("ONEME_MONITORING_ALLOW_INSECURE_HTTP", "true")
    System.put_env("ONEME_MONITORING_NOTIFY_MAX_ATTEMPTS", "2")
    System.put_env("ONEME_MONITORING_NOTIFY_RETRY_DELAY_MS", "0")

    on_exit(fn ->
      restore_env("ONEME_MONITORING_ALERT_URL", previous_url)
      restore_env("ONEME_MONITORING_ALERT_SECRET", previous_secret)
      restore_env("ONEME_MONITORING_ALLOW_INSECURE_HTTP", previous_http)
      restore_env("ONEME_MONITORING_NOTIFY_MAX_ATTEMPTS", previous_attempts)
      restore_env("ONEME_MONITORING_NOTIFY_RETRY_DELAY_MS", previous_delay)
      send(server, :stop)
    end)

    assert :ok = Monitoring.notify(%{status: "degraded"})
    assert_receive {:notification_request, request}, 1_000
    request = String.downcase(request)
    assert String.contains?(request, "x-oneme-api-version: v1")
    assert String.contains?(request, "x-oneme-monitoring-event-id: monitoring-")
    assert String.contains?(request, "idempotency-key: monitoring-")
    assert String.contains?(request, "oneme.monitoring")
  end

  defp start_retry_notification_server do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)
    parent = self()

    pid =
      spawn(fn ->
        {:ok, first_socket} = :gen_tcp.accept(listener)
        {:ok, _first_request} = :gen_tcp.recv(first_socket, 0, 5_000)

        :gen_tcp.send(
          first_socket,
          "HTTP/1.1 503 Service Unavailable\r\ncontent-length: 5\r\nconnection: close\r\n\r\nbusy\n"
        )

        :gen_tcp.close(first_socket)

        {:ok, second_socket} = :gen_tcp.accept(listener)
        {:ok, request} = :gen_tcp.recv(second_socket, 0, 5_000)
        send(parent, {:notification_request, request})

        :gen_tcp.send(
          second_socket,
          "HTTP/1.1 204 No Content\r\ncontent-length: 0\r\nconnection: close\r\n\r\n"
        )

        :gen_tcp.close(second_socket)
        :gen_tcp.close(listener)
      end)

    {pid, port}
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
