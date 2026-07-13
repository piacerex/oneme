defmodule Oneme.MonitoringTest do
  use ExUnit.Case

  alias Oneme.Monitoring

  test "returns not configured when no CDN endpoints are set" do
    previous = System.get_env("ONEME_CDN_URLS")
    System.delete_env("ONEME_CDN_URLS")

    on_exit(fn -> restore_env("ONEME_CDN_URLS", previous) end)

    assert %{status: "not_configured", endpoints: []} = Monitoring.check_cdn()
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
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
