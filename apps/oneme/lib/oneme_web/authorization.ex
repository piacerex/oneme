defmodule OnemeWeb.Authorization do
  @moduledoc "Controller authorization helpers for role-protected API actions."

  alias Oneme.Access

  def allowed?(conn, required_role),
    do: Access.authorized?(conn.assigns[:principal], required_role)

  def team_matches?(conn, nil), do: allowed?(conn, "viewer")

  def team_matches?(conn, team_id) do
    case conn.assigns[:principal] do
      %{team_id: ^team_id} -> true
      _ -> false
    end
  end
end
