defmodule OnemeWeb.BuilderLive do
  use OnemeWeb, :live_view

  alias Oneme.Avatars
  alias Oneme.Assets
  alias Oneme.Generations
  alias Oneme.Operations

  @default_config %{
    "parts" => %{
      "baseBody" => "body.basic_01",
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

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Avatar Builder")
     |> assign(:config, @default_config)
     |> assign(:parts, Assets.form_parts())
     |> assign(:avatar_name, "My oneme avatar")
     |> assign(:status, "編集内容はこのブラウザでプレビューできます。")
     |> assign(:face_export_consent, false)
     |> assign(:generation_job, nil)
     |> assign(:candidates, [])
     |> assign(:public_url, nil)
     |> assign(:widget_mode, Map.get(params, "widget") in ["1", "true"])
     |> assign(:parent_origin, valid_parent_origin(Map.get(params, "parent_origin")))
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

  def handle_event("generate_candidates", _params, socket) do
    case Generations.create_candidate_job(socket.assigns.config) do
      {:ok, job} ->
        {:noreply,
         socket
         |> assign(:generation_job, job)
         |> assign(:candidates, Generations.candidate_items(job))
         |> assign(:status, "3つの候補を生成しました。")}

      {:error, _reason} ->
        {:noreply, assign(socket, :status, "候補を生成できませんでした。")}
    end
  end

  def handle_event("apply_candidate", %{"candidate_id" => candidate_id}, socket) do
    case Enum.find(socket.assigns.candidates, &(&1["id"] == candidate_id)) do
      nil ->
        {:noreply, assign(socket, :status, "候補が見つかりませんでした。")}

      candidate ->
        generation_job =
          case socket.assigns.generation_job do
            nil ->
              nil

            job ->
              case Generations.feedback(job, candidate_id, "adopt") do
                {:ok, updated_job} -> updated_job
                _error -> job
              end
          end

        {:noreply,
         socket
         |> assign(:config, candidate["config"])
         |> assign(:generation_job, generation_job)
         |> assign(
           :candidates,
           update_candidate_status(socket.assigns.candidates, candidate_id, "adopted")
         )
         |> assign(:face_export_consent, face_export_consent?(candidate["config"]))
         |> assign(:status, "候補を適用しました。")}
    end
  end

  def handle_event("reject_candidate", %{"candidate_id" => candidate_id}, socket) do
    case socket.assigns.generation_job do
      nil ->
        {:noreply, assign(socket, :status, "先に候補を生成してください。")}

      job ->
        case Generations.feedback(job, candidate_id, "reject") do
          {:ok, updated_job} ->
            {:noreply,
             socket
             |> assign(:generation_job, updated_job)
             |> assign(:candidates, Generations.candidate_items(updated_job))
             |> assign(:status, "候補を却下しました。")}

          _error ->
            {:noreply, assign(socket, :status, "候補を却下できませんでした。")}
        end
    end
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
        next_socket =
          socket
          |> assign(:saved_avatar, avatar)
          |> assign(:public_url, nil)
          |> assign(:status, "保存しました。アバターID: #{avatar.id}")

        next_socket =
          if socket.assigns.widget_mode do
            push_event(next_socket, "avatar_saved", %{
              avatarId: avatar.id,
              publicUrl: "/avatars/#{avatar.id}"
            })
          else
            next_socket
          end

        {:noreply, next_socket}

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

  def handle_event("publish_avatar", _params, %{assigns: %{saved_avatar: nil}} = socket) do
    {:noreply, assign(socket, :status, "公開する前にアバターを保存してください。")}
  end

  def handle_event("publish_avatar", _params, socket) do
    case Avatars.update_avatar(socket.assigns.saved_avatar, %{visibility: "public"}) do
      {:ok, avatar} ->
        Operations.track_audit("avatar_published", %{
          resource_type: "avatar",
          resource_id: avatar.id
        })

        {:noreply,
         socket
         |> assign(:saved_avatar, avatar)
         |> assign(:public_url, "/avatars/#{avatar.id}")
         |> assign(:status, "公開URLを発行しました。")}

      {:error, changeset} ->
        {:noreply, assign(socket, :status, "公開できませんでした: #{inspect(changeset.errors)}")}
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

  defp update_candidate_status(candidates, candidate_id, status) do
    Enum.map(candidates, fn candidate ->
      if candidate["id"] == candidate_id,
        do: Map.put(candidate, "status", status),
        else: candidate
    end)
  end

  defp valid_parent_origin(nil), do: nil

  defp valid_parent_origin(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) ->
        port = if uri.port in [nil, URI.default_port(scheme)], do: "", else: ":#{uri.port}"
        "#{scheme}://#{host}#{port}"

      _ ->
        nil
    end
  end

  defp valid_parent_origin(_value), do: nil
end
