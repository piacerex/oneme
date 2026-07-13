defmodule Oneme.CdnMonitor do
  @moduledoc "Periodically refreshes the configured CDN health report."

  use GenServer

  alias Oneme.Monitoring

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def report, do: GenServer.call(__MODULE__, :report)
  def check_now, do: GenServer.call(__MODULE__, :check_now, 10_000)

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{report: refresh_report()}}
  end

  @impl true
  def handle_call(:report, _from, state), do: {:reply, state.report, state}

  @impl true
  def handle_call(:check_now, _from, state) do
    report = refresh_report()
    {:reply, report, %{state | report: report}}
  end

  @impl true
  def handle_info(:check, state) do
    schedule_check()
    {:noreply, %{state | report: refresh_report()}}
  end

  defp refresh_report do
    report = Monitoring.check_cdn()
    _ = Monitoring.record_probe(report)
    report = Map.put(report, :historicalSlo, Monitoring.recent_slo())
    _ = Monitoring.notify(report)
    report
  end

  defp schedule_check do
    Process.send_after(self(), :check, interval_ms())
  end

  defp interval_ms do
    case Integer.parse(System.get_env("ONEME_CDN_CHECK_INTERVAL_MS", "60000")) do
      {value, ""} when value >= 1_000 -> value
      _ -> 60_000
    end
  end
end
