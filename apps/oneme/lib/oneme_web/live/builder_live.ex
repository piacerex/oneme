defmodule OnemeWeb.BuilderLive do
  use OnemeWeb, :live_view

  alias Oneme.Avatars

  @default_config %{
    "parts" => %{
      "face" => "face.soft_01",
      "hair" => "hair.short_01",
      "top" => "top.basic_01",
      "bottom" => "bottom.basic_01",
      "shoes" => "shoes.basic_01",
      "accessory" => "accessory.none"
    },
    "colors" => %{"skin" => "#c98f6f", "hair" => "#2f2118"},
    "faceMorph" => %{"widthScale" => 1.0, "heightScale" => 1.06, "depth" => 0.5},
    "faceTexture" => %{"enabled" => false, "source" => "session", "exportConsent" => false}
  }

  @parts %{
    face: [{"Soft", "face.soft_01"}, {"Sharp", "face.sharp_01"}, {"Round", "face.round_01"}],
    hair: [{"Short", "hair.short_01"}, {"Bob", "hair.bob_01"}, {"Long", "hair.long_01"}],
    top: [{"Basic", "top.basic_01"}, {"Hoodie", "top.hoodie_01"}, {"Jacket", "top.jacket_01"}],
    bottom: [
      {"Basic", "bottom.basic_01"},
      {"Tapered", "bottom.tapered_01"},
      {"Skirt", "bottom.skirt_01"}
    ],
    shoes: [
      {"Basic", "shoes.basic_01"},
      {"Sneaker", "shoes.sneaker_01"},
      {"Boot", "shoes.boot_01"}
    ],
    accessory: [{"None", "accessory.none"}, {"Glasses", "accessory.glasses_01"}]
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Avatar Builder")
     |> assign(:config, @default_config)
     |> assign(:parts, @parts)
     |> assign(:avatar_name, "My oneme avatar")
     |> assign(:status, "編集内容はこのブラウザでプレビューできます。")
     |> assign(:face_export_consent, false)
     |> assign(:saved_avatar, nil)}
  end

  @impl true
  def handle_event("update_config", params, socket) do
    config = socket.assigns.config

    next_config =
      config
      |> Map.put("parts", Map.merge(config["parts"], Map.get(params, "parts", %{})))
      |> Map.put("colors", Map.merge(config["colors"], Map.get(params, "colors", %{})))
      |> put_face_texture(Map.get(params, "faceTexture", %{}))

    {:noreply,
     socket
     |> assign(:config, next_config)
     |> assign(:face_export_consent, face_export_consent?(next_config))}
  end

  def handle_event("face_analyzed", %{"face_morph" => face_morph}, socket) do
    config = socket.assigns.config
    face_texture = Map.get(config, "faceTexture", %{})

    next_config =
      config
      |> Map.put("faceMorph", Map.merge(Map.get(config, "faceMorph", %{}), face_morph))
      |> Map.put(
        "faceTexture",
        Map.merge(face_texture, %{"enabled" => true, "source" => "session"})
      )

    {:noreply,
     socket
     |> assign(:config, next_config)
     |> assign(:status, "顔の比率を疑似3Dパラメータへ反映しました。")}
  end

  def handle_event("clear_face", _params, socket) do
    config = socket.assigns.config
    face_texture = Map.get(config, "faceTexture", %{})
    next_config = Map.put(config, "faceTexture", Map.merge(face_texture, %{"enabled" => false}))

    {:noreply,
     socket
     |> assign(:config, next_config)
     |> assign(:status, "顔写真のマッピングをクリアしました。")
     |> push_event("face_mapping_cleared", %{})}
  end

  def handle_event("update_name", %{"avatar_name" => name}, socket) do
    {:noreply, assign(socket, :avatar_name, String.slice(name, 0, 80))}
  end

  def handle_event("save_avatar", _params, socket) do
    attrs = %{
      name: socket.assigns.avatar_name,
      config: socket.assigns.config,
      visibility: "private"
    }

    case Avatars.create_avatar(attrs) do
      {:ok, avatar} ->
        {:noreply,
         socket
         |> assign(:saved_avatar, avatar)
         |> assign(:status, "保存しました。アバターID: #{avatar.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :status, "保存できませんでした: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("load_latest", _params, socket) do
    case Avatars.latest_avatar() do
      nil ->
        {:noreply, assign(socket, :status, "保存済みアバターはまだありません。")}

      avatar ->
        {:noreply,
         socket
         |> assign(:avatar_name, avatar.name)
         |> assign(:config, avatar.config)
         |> assign(:face_export_consent, face_export_consent?(avatar.config))
         |> assign(:saved_avatar, avatar)
         |> assign(:status, "保存済みアバターを読み込みました。")}
    end
  end

  defp put_face_texture(config, params) do
    current = Map.get(config, "faceTexture", %{})
    export_consent = Map.get(params, "exportConsent", "false") in [true, "true", "on"]
    Map.put(config, "faceTexture", Map.merge(current, %{"exportConsent" => export_consent}))
  end

  defp face_export_consent?(config) do
    value =
      config
      |> Map.get("faceTexture", %{})
      |> Map.get("exportConsent", false)

    value in [true, "true", "on"]
  end
end
