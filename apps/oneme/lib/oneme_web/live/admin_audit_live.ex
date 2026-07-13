defmodule OnemeWeb.AdminAuditLive do
  use OnemeWeb, :live_view

  alias Oneme.Access
  alias Oneme.Operations

  @impl true
  def mount(_params, _session, socket) do
    authenticated = not Access.auth_required?()

    {:ok,
     socket
     |> assign(:page_title, "Audit Logs")
     |> assign(:principal, nil)
     |> assign(:authenticated, authenticated)
     |> assign(:status, nil)
     |> assign(:audits, if(authenticated, do: Operations.list_audits(), else: []))}
  end

  @impl true
  def handle_event("authenticate", %{"api_key" => raw_key}, socket) do
    case Access.authenticate_api_key(String.trim(raw_key)) do
      {:ok, principal} ->
        if Access.authorized?(principal, "admin") do
          {:noreply,
           socket
           |> assign(:principal, principal)
           |> assign(:authenticated, true)
           |> assign(:audits, Operations.list_audits())
           |> assign(:status, "管理者として認証しました。")}
        else
          {:noreply, assign(socket, :status, "管理者APIキーを確認できませんでした。")}
        end

      _error ->
        {:noreply, assign(socket, :status, "管理者APIキーを確認できませんでした。")}
    end
  end

  def handle_event("refresh", _params, socket) do
    if authorized?(socket) do
      {:noreply,
       socket
       |> assign(:audits, Operations.list_audits())
       |> assign(:status, "監査ログを更新しました。")}
    else
      {:noreply, assign(socket, :status, "管理者権限が必要です。")}
    end
  end

  def handle_event("prune", %{"before" => before}, socket) do
    with true <- authorized?(socket),
         {:ok, before} <- parse_before(before) do
      deleted = Operations.prune_audits_before(before)

      {:noreply,
       socket
       |> assign(:audits, Operations.list_audits())
       |> assign(:status, "#{deleted}件の監査ログを削除しました。")}
    else
      false -> {:noreply, assign(socket, :status, "管理者権限が必要です。")}
      {:error, :invalid_before} -> {:noreply, assign(socket, :status, "削除基準日時を確認してください。")}
    end
  end

  defp authorized?(socket),
    do: socket.assigns.authenticated and Access.authorized?(socket.assigns.principal, "admin")

  defp parse_before(value) when is_binary(value) do
    value = String.trim(value)

    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> parse_local_datetime(value)
    end
  end

  defp parse_before(_value), do: {:error, :invalid_before}

  defp parse_local_datetime(value) do
    case DateTime.from_iso8601(value <> ":00Z") do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, :invalid_before}
    end
  end

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")

  defp metadata_json(metadata), do: Jason.encode!(metadata)
end
