defmodule OnemeWeb.APIAuth do
  @moduledoc "Optional development auth and production API-key authentication."

  import Plug.Conn

  alias Oneme.Access

  def init(opts), do: opts

  def call(conn, _opts) do
    case bearer_token(conn) do
      nil -> maybe_require(conn)
      token -> authenticate(conn, token)
    end
  end

  defp authenticate(conn, token) do
    case Access.authenticate_api_key(token) do
      {:ok, principal} -> assign(conn, :principal, principal)
      {:error, :invalid_api_key} -> unauthorized(conn, "invalid_api_key")
    end
  end

  defp maybe_require(conn) do
    if Access.auth_required?() and not Access.public_path?(conn.request_path) do
      unauthorized(conn, "authentication_required")
    else
      assign(conn, :principal, nil)
    end
  end

  defp bearer_token(conn) do
    authorization = List.first(get_req_header(conn, "authorization"))
    api_key = List.first(get_req_header(conn, "x-oneme-api-key"))

    cond do
      is_binary(authorization) and String.starts_with?(authorization, "Bearer ") ->
        String.trim_leading(authorization, "Bearer ")

      is_binary(api_key) and api_key != "" ->
        api_key

      true ->
        nil
    end
  end

  defp unauthorized(conn, error) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: error}))
    |> halt()
  end
end
