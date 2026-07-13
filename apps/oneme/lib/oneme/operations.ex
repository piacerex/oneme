defmodule Oneme.Operations do
  @moduledoc "Operational health, usage, and audit records."

  import Ecto.Query

  alias Oneme.Operations.{AuditLog, UsageEvent}
  alias Oneme.Repo

  def health do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _result} -> %{status: "ok", database: "ok"}
      {:error, _reason} -> %{status: "degraded", database: "error"}
    end
  end

  def record_usage(event_type, attrs \\ %{}) do
    %UsageEvent{}
    |> UsageEvent.changeset(%{
      event_type: event_type,
      subject_type: Map.get(attrs, :subject_type),
      subject_id: normalize_id(Map.get(attrs, :subject_id)),
      metadata: normalize_metadata(Map.get(attrs, :metadata, %{}))
    })
    |> Repo.insert()
  end

  def record_audit(action, attrs \\ %{}) do
    %AuditLog{}
    |> AuditLog.changeset(%{
      action: action,
      resource_type: Map.get(attrs, :resource_type),
      resource_id: normalize_id(Map.get(attrs, :resource_id)),
      metadata: normalize_metadata(Map.get(attrs, :metadata, %{}))
    })
    |> Repo.insert()
  end

  def track_usage(event_type, attrs \\ %{}) do
    record_usage(event_type, attrs)
    :ok
  rescue
    _error -> :error
  end

  def track_audit(action, attrs \\ %{}) do
    record_audit(action, attrs)
    :ok
  rescue
    _error -> :error
  end

  def list_audits(limit \\ 100) do
    AuditLog
    |> order_by(desc: :inserted_at)
    |> limit(^min(max(limit, 1), 500))
    |> Repo.all()
  end

  def prune_audits_before(%DateTime{} = before) do
    {count, _} = Repo.delete_all(from(log in AuditLog, where: log.inserted_at < ^before))
    count
  end

  defp normalize_id(nil), do: nil
  defp normalize_id(value), do: to_string(value)

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}
end
