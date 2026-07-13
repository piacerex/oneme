defmodule Oneme.MonitoringProbeTest do
  use Oneme.DataCase

  alias Oneme.Monitoring
  alias Oneme.Monitoring.ProbeRun
  alias Oneme.Repo

  test "records endpoint counts without persisting endpoint URLs" do
    report = %{
      status: "degraded",
      endpoints: [
        %{ok: true, url: "https://cdn.example.com/private-token", responseMs: 40},
        %{ok: false, url: "https://cdn.example.com/other-token", responseMs: 0}
      ],
      alerts: [
        %{
          code: "cdn_endpoint_unhealthy",
          severity: "critical",
          url: "https://cdn.example.com/private-token"
        }
      ]
    }

    assert {:ok, %ProbeRun{} = run} = Monitoring.record_probe(report)
    assert run.endpoint_count == 2
    assert run.available_count == 1
    assert run.availability_percent == 50.0
    refute Jason.encode!(run.report) =~ "private-token"
    refute Jason.encode!(run.report) =~ "cdn.example.com"

    assert %{
             probeCount: 1,
             endpointCount: 2,
             availableEndpointCount: 1,
             probeAvailabilityPercent: 50.0,
             lastStatus: "degraded"
           } = Monitoring.recent_slo()

    assert Repo.get!(ProbeRun, run.id).status == "degraded"
  end

  test "does not create an SLO sample when monitoring is not configured" do
    assert {:ok, nil} = Monitoring.record_probe(%{status: "not_configured", endpoints: []})
    assert Monitoring.recent_slo().probeCount == 0
  end
end
