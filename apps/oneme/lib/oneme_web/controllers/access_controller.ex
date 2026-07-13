defmodule OnemeWeb.AccessController do
  use OnemeWeb, :controller

  alias Oneme.Access
  alias Oneme.Operations

  def me(conn, _params) do
    case conn.assigns[:principal] do
      nil ->
        json(conn, %{authenticated: false, authRequired: Access.auth_required?()})

      principal ->
        json(conn, %{
          authenticated: true,
          authRequired: Access.auth_required?(),
          principal: %{
            apiKeyId: principal.api_key_id,
            keyPrefix: principal.key_prefix,
            teamId: principal.team_id,
            teamSlug: principal.team_slug,
            role: principal.role,
            scopes: principal.scopes
          }
        })
    end
  end

  def bootstrap(conn, params) do
    with :ok <- valid_bootstrap_token(conn),
         {:ok, result, raw_key} <- Access.bootstrap(params) do
      Operations.track_audit("team_bootstrapped", %{
        resource_type: "team",
        resource_id: result.team.id,
        metadata: %{"keyPrefix" => result.api_key.key_prefix}
      })

      conn
      |> put_status(:created)
      |> json(%{
        team: %{id: result.team.id, name: result.team.name, slug: result.team.slug},
        user: %{id: result.user.id, externalId: result.user.external_id, email: result.user.email},
        apiKey: raw_key,
        apiKeyId: result.api_key.id,
        apiKeyPrefix: result.api_key.key_prefix
      })
    else
      {:error, :invalid_bootstrap_token} ->
        forbidden(conn, "invalid_bootstrap_token")

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  def create_api_key(conn, params) do
    team_id = normalize_team_id(Map.get(params, "teamId"))

    key_attrs = %{
      name: Map.get(params, "name", "API key"),
      role: Map.get(params, "role", "editor")
    }

    with :ok <- authorize_team_admin(conn, team_id),
         {:ok, api_key, raw_key} <- Access.create_api_key(team_id, key_attrs) do
      conn
      |> put_status(:created)
      |> json(%{
        apiKey: raw_key,
        apiKeyId: api_key.id,
        apiKeyPrefix: api_key.key_prefix,
        role: api_key.role,
        teamId: api_key.team_id
      })
    else
      {:error, :forbidden} ->
        forbidden(conn, "forbidden")

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  def revoke_api_key(conn, %{"id" => id}) do
    with %{team_id: team_id} <- Access.get_api_key(id),
         :ok <- authorize_team_admin(conn, team_id),
         {:ok, _api_key} <- Access.revoke_api_key(id) do
      send_resp(conn, :no_content, "")
    else
      nil -> send_resp(conn, :not_found, "api key not found")
      {:error, :forbidden} -> forbidden(conn, "forbidden")
      {:error, _reason} -> send_resp(conn, :not_found, "api key not found")
    end
  end

  defp valid_bootstrap_token(conn) do
    configured = System.get_env("ONEME_AUTH_BOOTSTRAP_TOKEN")
    supplied = List.first(get_req_header(conn, "x-oneme-bootstrap-token"))

    cond do
      is_binary(configured) and configured != "" and is_binary(supplied) ->
        if Plug.Crypto.secure_compare(configured, supplied),
          do: :ok,
          else: {:error, :invalid_bootstrap_token}

      is_nil(configured) and not Access.auth_required?() ->
        :ok

      true ->
        {:error, :invalid_bootstrap_token}
    end
  end

  defp authorize_team_admin(conn, team_id) do
    principal = conn.assigns[:principal]

    if is_integer(team_id) and Access.authorized?(principal, "admin") and
         principal.team_id == team_id,
       do: :ok,
       else: {:error, :forbidden}
  end

  defp normalize_team_id(team_id) when is_integer(team_id), do: team_id

  defp normalize_team_id(team_id) when is_binary(team_id) do
    case Integer.parse(team_id) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp normalize_team_id(_team_id), do: nil

  defp forbidden(conn, error), do: conn |> put_status(:forbidden) |> json(%{error: error})
end
