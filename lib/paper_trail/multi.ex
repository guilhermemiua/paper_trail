defmodule PaperTrail.Multi do
  import Ecto.Changeset

  alias Ecto.Changeset
  alias PaperTrail
  alias PaperTrail.Version
  alias PaperTrail.RepoClient
  alias PaperTrail.Serializer

  @type multi :: Ecto.Multi.t()
  @type changeset :: Changeset.t()
  @type options :: PaperTrail.options()
  @type queryable :: PaperTrail.queryable()
  @type updates :: PaperTrail.updates()
  @type struct_or_changeset :: Ecto.Schema.t() | Changeset.t()
  @type result ::
          {:ok, any()}
          | {:error, any()}
          | {:error, Ecto.Multi.name(), any(), %{required(Ecto.Multi.name()) => any()}}

  @default_model_key :model
  @default_version_key :version

  defdelegate new(), to: Ecto.Multi
  defdelegate append(lhs, rhs), to: Ecto.Multi
  defdelegate error(multi, name, value), to: Ecto.Multi
  defdelegate merge(multi, merge), to: Ecto.Multi
  defdelegate merge(multi, mod, fun, args), to: Ecto.Multi
  defdelegate prepend(lhs, rhs), to: Ecto.Multi
  defdelegate run(multi, name, run), to: Ecto.Multi
  defdelegate run(multi, name, mod, fun, args), to: Ecto.Multi
  defdelegate to_list(multi), to: Ecto.Multi
  defdelegate make_version_struct(version, model, options), to: Serializer
  defdelegate make_version_query(version, queryable, changes, options), to: Serializer
  defdelegate get_sequence_from_model(changeset, options \\ []), to: Serializer
  defdelegate serialize(data, options, event), to: Serializer
  defdelegate get_sequence_id(table_name, options \\ []), to: Serializer
  defdelegate add_prefix(changeset, prefix), to: Serializer
  defdelegate get_item_type(data), to: Serializer
  defdelegate get_model_id(model), to: Serializer

  @spec insert(multi, changeset, options) :: multi
  def insert(%Ecto.Multi{} = multi, changeset, options \\ []) do
    model_key = get_model_key(options)
    version_key = get_version_key(options)

    case RepoClient.strict_mode(options) do
      true ->
        multi
        |> Ecto.Multi.run(:initial_version, fn repo, %{} ->
          version_id = get_sequence_id("versions", options) + 1

          changeset_data =
            Map.get(changeset, :data, changeset)
            |> Map.merge(%{
              id: get_sequence_from_model(changeset, options) + 1,
              first_version_id: version_id,
              current_version_id: version_id
            })

          initial_version = make_version_struct(%{event: "insert"}, changeset_data, options)
          repo.insert(initial_version)
        end)
        |> Ecto.Multi.run(model_key, fn repo, %{initial_version: initial_version} ->
          updated_changeset =
            changeset
            |> change(%{
              first_version_id: initial_version.id,
              current_version_id: initial_version.id
            })

          repo.insert(updated_changeset)
        end)
        |> Ecto.Multi.run(version_key, fn repo,
                                          %{
                                            :initial_version => initial_version,
                                            ^model_key => model
                                          } ->
          target_version =
            make_version_struct(%{event: "insert"}, model, options)
            |> serialize(options, "insert")

          Version.changeset(initial_version, target_version) |> repo.update
        end)

      _ ->
        multi
        |> Ecto.Multi.insert(model_key, changeset)
        |> Ecto.Multi.run(version_key, fn repo, %{^model_key => model} ->
          version = make_version_struct(%{event: "insert"}, model, options)
          repo.insert(version)
        end)
    end
  end

  @spec insert_all(multi, list(map()), options) :: multi
  def insert_all(
        %Ecto.Multi{} = multi,
        entries,
        options \\ []
      ) do
    model_key = get_model_key(options)
    version_key = get_version_key(options)
    source = options[:source]

    case RepoClient.strict_mode(options) do
      true ->
        raise "Strict mode not implemented for insert_all"

      _ ->
        multi
        |> Ecto.Multi.insert_all(model_key, source, entries, options)
        |> Ecto.Multi.merge(fn %{^model_key => {_count, models}} ->
          (models || [])
          |> Enum.reduce(Ecto.Multi.new(), fn model, multi ->
            version = make_version_struct(%{event: "insert"}, model, options)
            Ecto.Multi.insert(multi, {version_key, version.item_id}, version)
          end)
        end)
    end
  end

  @spec update(multi, changeset, options) :: multi
  def update(
        %Ecto.Multi{} = multi,
        changeset,
        options \\ []
      ) do
    model_key = get_model_key(options)
    version_key = get_version_key(options)

    case RepoClient.strict_mode(options) do
      true ->
        multi
        |> Ecto.Multi.run(:initial_version, fn repo, %{} ->
          version_data =
            changeset.data
            |> Map.merge(%{
              current_version_id: get_sequence_id("versions", options)
            })

          target_changeset = changeset |> Map.merge(%{data: version_data})
          target_version = make_version_struct(%{event: "update"}, target_changeset, options)
          repo.insert(target_version)
        end)
        |> Ecto.Multi.run(model_key, fn repo, %{initial_version: initial_version} ->
          updated_changeset = changeset |> change(%{current_version_id: initial_version.id})
          repo.update(updated_changeset)
        end)
        |> Ecto.Multi.run(version_key, fn repo, %{initial_version: initial_version} ->
          new_item_changes =
            initial_version.item_changes
            |> Map.merge(%{
              current_version_id: initial_version.id
            })

          initial_version |> change(%{item_changes: new_item_changes}) |> repo.update
        end)

      _ ->
        multi
        |> Ecto.Multi.update(model_key, changeset)
        |> Ecto.Multi.run(version_key, fn repo, _changes ->
          version = make_version_struct(%{event: "update"}, changeset, options)

          if changeset.changes == %{} do
            {:ok, nil}
          else
            repo.insert(version)
          end
        end)
    end
  end

  @spec update_all(multi, queryable, updates, options) :: multi
  def update_all(
        %Ecto.Multi{} = multi,
        queryable,
        [set: changes] = updates,
        options \\ []
      ) do
    model_key = get_model_key(options)
    version_key = get_version_key(options)
    entries_query = make_version_query(%{event: "update"}, queryable, changes, options)
    returning = !!options[:returning] && RepoClient.return_operation(options) == version_key

    case RepoClient.strict_mode(options) do
      true ->
        raise "Strict mode not implemented for update_all"

      _ ->
        multi
        |> Ecto.Multi.insert_all(version_key, Version, entries_query, returning: returning)
        |> Ecto.Multi.update_all(model_key, queryable, updates)
    end
  end

  @spec delete(multi, struct_or_changeset, options) :: multi
  def delete(
        %Ecto.Multi{} = multi,
        struct_or_changeset,
        options \\ []
      ) do
    model_key = get_model_key(options)
    version_key = get_version_key(options)

    multi
    |> Ecto.Multi.delete(model_key, struct_or_changeset, options)
    |> Ecto.Multi.run(version_key, fn repo, %{} ->
      version = make_version_struct(%{event: "delete"}, struct_or_changeset, options)
      repo.insert(version, options)
    end)
  end

  @spec soft_delete(multi, struct_or_changeset, options) :: multi
  def soft_delete(
        %Ecto.Multi{} = multi,
        struct_or_changeset,
        options \\ []
      ) do
    repo = RepoClient.repo(options)
    model_key = get_model_key(options)
    version_key = get_version_key(options)

    multi
    |> Ecto.Multi.run(model_key, fn _, _ -> repo.soft_delete(struct_or_changeset) end)
    |> Ecto.Multi.run(version_key, fn repo, %{} ->
      version = make_version_struct(%{event: "soft_delete"}, struct_or_changeset, options)
      repo.insert(version, options)
    end)
  end

  @spec soft_delete_all(multi, queryable, options) :: multi
  def soft_delete_all(
        %Ecto.Multi{} = multi,
        queryable,
        options \\ []
      ) do
    changes = [deleted_at: DateTime.utc_now()]
    updates = [set: changes]
    model_key = get_model_key(options)
    version_key = get_version_key(options)
    entries_query = make_version_query(%{event: "soft_delete"}, queryable, changes, options)
    returning = !!options[:returning] && RepoClient.return_operation(options) == version_key

    case RepoClient.strict_mode(options) do
      true ->
        raise "Strict mode not implemented for soft_delete_all"

      _ ->
        multi
        |> Ecto.Multi.insert_all(version_key, Version, entries_query, returning: returning)
        |> Ecto.Multi.update_all(model_key, queryable, updates)
    end
  end

  @spec commit(multi, options) :: result
  def commit(%Ecto.Multi{} = multi, options \\ []) do
    model_key = get_model_key(options)
    repo = RepoClient.repo(options)

    transaction = repo.transaction(multi)

    case RepoClient.strict_mode(options) do
      true ->
        case transaction do
          {:error, ^model_key, changeset, %{}} ->
            filtered_changes =
              Map.drop(changeset.changes, [:current_version_id, :first_version_id])

            {:error, Map.merge(changeset, %{repo: repo, changes: filtered_changes})}

          {:ok, map} ->
            {:ok, map |> Map.drop([:initial_version]) |> return_operation(options)}
        end

      _ ->
        case transaction do
          {:error, ^model_key, changeset, %{}} -> {:error, Map.merge(changeset, %{repo: repo})}
          {:ok, result} -> {:ok, return_operation(result, options)}
        end
    end
  end

  @spec get_model_key(Keyword.t()) :: PaperTrail.multi_name()
  defp get_model_key(options), do: options[:model_key] || @default_model_key

  @spec get_version_key(Keyword.t()) :: PaperTrail.multi_name()
  defp get_version_key(options), do: options[:version_key] || @default_version_key

  @spec return_operation(map, Keyword.t()) :: any
  defp return_operation(result, options) do
    case RepoClient.return_operation(options) do
      nil -> result
      operation -> Map.fetch!(result, operation)
    end
  end
end
