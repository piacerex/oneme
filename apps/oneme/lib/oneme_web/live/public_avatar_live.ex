defmodule OnemeWeb.PublicAvatarLive do
  use OnemeWeb, :live_view

  alias Oneme.Avatars

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Avatars.get_avatar(id) do
      %{visibility: "public"} = avatar ->
        {:ok, assign(socket, page_title: avatar.name, avatar: avatar, unavailable: false)}

      _ ->
        {:ok, assign(socket, page_title: "Avatar unavailable", avatar: nil, unavailable: true)}
    end
  end
end
