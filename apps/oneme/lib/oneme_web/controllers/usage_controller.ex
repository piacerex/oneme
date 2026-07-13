defmodule OnemeWeb.UsageController do
  use OnemeWeb, :controller

  alias Oneme.Access
  alias Oneme.Usage

  def index(conn, params) do
    case conn.assigns[:principal] do
      %{team_id: team_id} = principal ->
        if Access.authorized?(principal, "admin") do
          from_date = parse_date(Map.get(params, "from")) || Date.add(Date.utc_today(), -30)
          to_date = parse_date(Map.get(params, "to")) || Date.utc_today()

          json(conn, %{
            teamId: team_id,
            from: from_date,
            to: to_date,
            metrics: Usage.summary(team_id, from_date, to_date)
          })
        else
          forbidden(conn)
        end

      _ ->
        forbidden(conn)
    end
  end

  defp forbidden(conn), do: conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

  defp parse_date(nil), do: nil

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
