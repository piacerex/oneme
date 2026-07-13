defmodule Oneme.AvatarsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Oneme.Avatars` context.
  """

  @doc """
  Generate a avatar.
  """
  def avatar_fixture(attrs \\ %{}) do
    {:ok, avatar} =
      attrs
      |> Enum.into(%{
        config: %{},
        name: "some name",
        visibility: "private"
      })
      |> Oneme.Avatars.create_avatar()

    avatar
  end
end
