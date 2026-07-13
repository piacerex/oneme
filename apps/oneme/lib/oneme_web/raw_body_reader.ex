defmodule OnemeWeb.RawBodyReader do
  @moduledoc "Keeps the exact request body available for signature verification."

  import Plug.Conn

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, assign_body(conn, body)}
      {:more, body, conn} -> {:more, body, assign_body(conn, body)}
    end
  end

  defp assign_body(conn, body),
    do: assign(conn, :raw_body, Map.get(conn.assigns, :raw_body, "") <> body)
end
