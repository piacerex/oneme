defmodule Oneme.AvatarsTest do
  use Oneme.DataCase

  alias Oneme.Avatars

  describe "avatars" do
    alias Oneme.Avatars.Avatar

    import Oneme.AvatarsFixtures

    @invalid_attrs %{name: nil, config: nil, visibility: nil}

    test "list_avatars/0 returns all avatars" do
      avatar = avatar_fixture()
      assert Avatars.list_avatars() == [avatar]
    end

    test "get_avatar!/1 returns the avatar with given id" do
      avatar = avatar_fixture()
      assert Avatars.get_avatar!(avatar.id) == avatar
    end

    test "create_avatar/1 with valid data creates a avatar" do
      valid_attrs = %{name: "some name", config: %{}, visibility: "private"}

      assert {:ok, %Avatar{} = avatar} = Avatars.create_avatar(valid_attrs)
      assert avatar.name == "some name"
      assert avatar.config == %{}
      assert avatar.visibility == "private"
    end

    test "create_avatar/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Avatars.create_avatar(@invalid_attrs)
    end

    test "update_avatar/2 with valid data updates the avatar" do
      avatar = avatar_fixture()

      update_attrs = %{
        name: "some updated name",
        config: %{},
        visibility: "public"
      }

      assert {:ok, %Avatar{} = avatar} = Avatars.update_avatar(avatar, update_attrs)
      assert avatar.name == "some updated name"
      assert avatar.config == %{}
      assert avatar.visibility == "public"
    end

    test "update_avatar/2 with invalid data returns error changeset" do
      avatar = avatar_fixture()
      assert {:error, %Ecto.Changeset{}} = Avatars.update_avatar(avatar, @invalid_attrs)
      assert avatar == Avatars.get_avatar!(avatar.id)
    end

    test "delete_avatar/1 deletes the avatar" do
      avatar = avatar_fixture()
      assert {:ok, %Avatar{}} = Avatars.delete_avatar(avatar)
      assert_raise Ecto.NoResultsError, fn -> Avatars.get_avatar!(avatar.id) end
    end

    test "change_avatar/1 returns a avatar changeset" do
      avatar = avatar_fixture()
      assert %Ecto.Changeset{} = Avatars.change_avatar(avatar)
    end
  end
end
