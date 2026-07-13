defmodule OnemeWeb.BuilderLiveTest do
  use OnemeWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the builder and updates the preview config", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "顔写真からつくる、あなたの3Dアバター"
    assert has_element?(view, "#avatar-preview[data-config]")

    html =
      render_change(view, "update_config", %{
        "parts" => %{"top" => "top.jacket_01"},
        "colors" => %{"skin" => "#d5a083"}
      })

    assert html =~ "top.jacket_01"
    assert html =~ "#d5a083"
  end

  test "saves and loads the latest avatar", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = render_click(view, "save_avatar")
    assert html =~ "保存しました。アバターID:"

    html = render_click(view, "load_latest")
    assert html =~ "保存済みアバターを読み込みました。"
  end
end
