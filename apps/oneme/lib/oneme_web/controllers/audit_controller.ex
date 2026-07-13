defmodule OnemeWeb.AuditController do
  use OnemeWeb, :controller

  alias Oneme.Access
  alias Oneme.Operations

  def index(conn, params) do
    with :ok <- admin?(conn) do
      limit = parse_limit(Map.get(params, "limit"))

      json(conn, %{
        audits:
          Enum.map(Operations.list_audits(limit), fn audit ->
            %{
              id: audit.id,
              action: audit.action,
              resourceType: audit.resource_type,
              resourceId: audit.resource_id,
              metadata: audit.metadata,
              createdAt: audit.inserted_at
            }
          end)
      })
    else
      {:error, :forbidden} -> forbidden(conn)
    end
  end

  def prune(conn, %{"before" => before}) do
    with :ok <- admin?(conn),
         {:ok, before, _offset} <- DateTime.from_iso8601(before) do
      count = Operations.prune_audits_before(before)
      json(conn, %{deleted: count, before: before})
    else
      {:error, :forbidden} -> forbidden(conn)
      _ -> conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_before"})
    end
  end

  def prune(conn, _params),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_before"})

  defp admin?(conn) do
    case conn.assigns[:principal] do
      principal when is_map(principal) ->
        if Access.authorized?(principal, "admin"), do: :ok, else: {:error, :forbidden}

      _ ->
        {:error, :forbidden}
    end
  end

  defp parse_limit(nil), do: 100

  defp parse_limit(value) do
    case Integer.parse(value) do
      {limit, ""} -> limit
      _ -> 100
    end
  end

  defp forbidden(conn), do: conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
end
