defmodule Oneme.Access do
  @moduledoc "Team, role, and hashed API-key access control."

  import Ecto.Query

  alias Oneme.Access.{ApiKey, Team, TeamMember, User}
  alias Oneme.Repo

  @roles ~w(viewer editor admin owner)
  @role_rank %{"viewer" => 1, "editor" => 2, "admin" => 3, "owner" => 4}

  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def create_team(attrs) do
    %Team{}
    |> Team.changeset(attrs)
    |> Repo.insert()
  end

  def add_member(attrs) do
    %TeamMember{}
    |> TeamMember.changeset(attrs)
    |> Repo.insert()
  end

  def create_api_key(team_id, attrs \\ %{}) do
    raw_key = "oneme_" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    key_hash = digest(raw_key)

    changes =
      attrs
      |> Map.put(:team_id, team_id)
      |> Map.put(:key_prefix, String.slice(raw_key, 0, 14))
      |> Map.put(:key_hash, key_hash)
      |> Map.put_new(:name, "Default API key")
      |> Map.put_new(:role, "editor")
      |> Map.put_new(:scopes, %{})

    case %ApiKey{} |> ApiKey.changeset(changes) |> Repo.insert() do
      {:ok, api_key} -> {:ok, api_key, raw_key}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def bootstrap(attrs) do
    raw_key = "oneme_" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    user_attrs = %{
      external_id:
        Map.get(attrs, :external_id) || Map.get(attrs, "externalId") || "bootstrap-owner",
      email: Map.get(attrs, :email) || Map.get(attrs, "email") || "owner@example.invalid",
      name: Map.get(attrs, :user_name) || Map.get(attrs, "userName") || "Owner"
    }

    team_attrs = %{
      name: Map.get(attrs, :team_name) || Map.get(attrs, "teamName") || "oneme team",
      slug: Map.get(attrs, :team_slug) || Map.get(attrs, "teamSlug") || "oneme-team"
    }

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:user, User.changeset(%User{}, user_attrs))
      |> Ecto.Multi.insert(:team, Team.changeset(%Team{}, team_attrs))
      |> Ecto.Multi.run(:member, fn _repo, changes ->
        %TeamMember{}
        |> TeamMember.changeset(%{
          team_id: changes.team.id,
          user_id: changes.user.id,
          role: "owner"
        })
        |> Repo.insert()
      end)
      |> Ecto.Multi.run(:api_key, fn _repo, changes ->
        key_attrs = %{
          team_id: changes.team.id,
          name: "Bootstrap key",
          key_prefix: String.slice(raw_key, 0, 14),
          key_hash: digest(raw_key),
          role: "owner",
          scopes: %{}
        }

        %ApiKey{}
        |> ApiKey.changeset(key_attrs)
        |> Repo.insert()
      end)

    case Repo.transaction(multi) do
      {:ok, result} -> {:ok, result, raw_key}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  def authenticate_api_key(raw_key) when is_binary(raw_key) and raw_key != "" do
    key_hash = digest(raw_key)

    ApiKey
    |> join(:inner, [key], team in Team, on: team.id == key.team_id)
    |> where([key, _team], key.key_hash == ^key_hash and is_nil(key.revoked_at))
    |> select([key, team], %{api_key: key, team: team})
    |> Repo.one()
    |> case do
      nil ->
        {:error, :invalid_api_key}

      %{api_key: api_key, team: team} ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        Repo.update_all(from(key in ApiKey, where: key.id == ^api_key.id),
          set: [last_used_at: now]
        )

        {:ok,
         %{
           api_key_id: api_key.id,
           team_id: team.id,
           team_slug: team.slug,
           role: api_key.role,
           scopes: api_key.scopes,
           key_prefix: api_key.key_prefix
         }}
    end
  end

  def authenticate_api_key(_raw_key), do: {:error, :invalid_api_key}

  def revoke_api_key(id) do
    case Repo.get(ApiKey, id) do
      nil -> {:error, :not_found}
      api_key -> api_key |> ApiKey.changeset(%{revoked_at: DateTime.utc_now()}) |> Repo.update()
    end
  end

  def get_api_key(id), do: Repo.get(ApiKey, id)

  def authorized?(nil, _required_role), do: not auth_required?()

  def authorized?(principal, required_role)
      when is_map(principal) and required_role in @roles do
    role = Map.get(principal, :role, "viewer")
    Map.get(@role_rank, role, 0) >= Map.get(@role_rank, required_role, 0)
  end

  def authorized?(_principal, _required_role), do: false

  def auth_required? do
    System.get_env("ONEME_AUTH_REQUIRED", "false") in ["1", "true", "TRUE", "yes"]
  end

  def public_path?(path) do
    path in ["/api/health", "/api/parts", "/api/auth/me", "/api/auth/bootstrap"] or
      String.ends_with?(path, "/public") or
      String.ends_with?(path, "/config") or
      String.ends_with?(path, "/model")
  end

  defp digest(raw_key), do: :crypto.hash(:sha256, raw_key) |> Base.encode16(case: :lower)
end
