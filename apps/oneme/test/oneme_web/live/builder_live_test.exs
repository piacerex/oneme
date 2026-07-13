defmodule OnemeWeb.BuilderLiveTest do
  use OnemeWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the builder and updates the preview config", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "顔写真からつくる、あなたの3Dアバター"
    assert has_element?(view, "#avatar-preview[data-config]")
    assert has_element?(view, "#export-glb")
    assert has_element?(view, "#export-vrm")
    assert has_element?(view, "#generate-candidates")
    assert has_element?(view, "input[name='faceMorph[widthScale]']")
    assert has_element?(view, "button", "公開URLを発行")

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

  test "widget mode accepts a valid parent origin", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/widget?widget=1&parent_origin=https%3A%2F%2Fexample.com")

    assert html =~ "data-parent-origin=\"https://example.com\""
    assert has_element?(view, ".widget-shell")
  end

  test "stores face morph parameters and export consent without the photo", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      render_change(view, "update_config", %{
        "faceTexture" => %{"exportConsent" => "true"}
      })

    assert html =~ "同意した顔テクスチャをGLB/FBX/VRMへ含める"
    assert html =~ "id=\"face-export-consent\""

    html =
      render_hook(view, "face_analyzed", %{
        "face_detected" => true,
        "face_morph" => %{"widthScale" => 1.08, "heightScale" => 1.12, "depth" => 0.55}
      })

    assert html =~ "顔の比率を疑似3Dパラメータへ反映しました。"
    refute html =~ "data:image"

    html = render_click(view, "clear_face")
    assert html =~ "顔写真のマッピングをクリアしました。"

    html = render_change(view, "update_config", %{"faceMorph" => %{"widthScale" => "1.12"}})
    assert html =~ "value=\"1.12\""
  end

  test "generates and applies a recommendation candidate", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = render_click(view, "generate_candidates")
    assert html =~ "Soft Studio"
    assert html =~ "Studio Edge"
    assert html =~ "Expressive Color"

    html = render_click(view, "apply_candidate", %{"candidate_id" => "candidate-studio"})
    assert html =~ "候補を適用しました。"
    assert html =~ "face.sharp_01"

    html = render_click(view, "reject_candidate", %{"candidate_id" => "candidate-expressive"})
    assert html =~ "候補を却下しました。"
  end
end
