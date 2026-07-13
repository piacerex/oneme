defmodule OnemeWeb.PageController do
  use OnemeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
