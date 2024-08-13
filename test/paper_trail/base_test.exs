defmodule PaperTrailTest do
  use ExUnit.Case

  import Ecto.Query

  alias PaperTrail.Version
  alias SimpleCompany, as: Company
  alias SimplePerson, as: Person
  alias PaperTrail.Serializer

  @repo PaperTrail.RepoClient.repo()
  @create_company_params %{
    name: "Acme LLC",
    is_active: true,
    city: "Greenwich",
    location: %{country: "Brazil"},
    email_options: %{newsletter_enabled: false}
  }
  @update_company_params %{
    city: "Hong Kong",
    website: "http://www.acme.com",
    facebook: "acme.llc",
    location: %{country: "Chile"},
    email_options: %{newsletter_enabled: true}
  }

  defmodule CustomPaperTrail do
    use PaperTrail,
      repo: PaperTrail.Repo,
      strict_mode: false
  end

  doctest PaperTrail

  setup_all do
    Code.eval_file("lib/paper_trail.ex")
    Code.eval_file("lib/version.ex")
    :ok
  end

  setup do
    @repo.delete_all(Person)
    @repo.delete_all(Company)
    @repo.delete_all(Version)

    on_exit(fn ->
      @repo.delete_all(Person)
      @repo.delete_all(Company)
      @repo.delete_all(Version)
    end)

    :ok
  end

  test "creating a company creates a company version with correct attributes" do
    user = create_user()
    {:ok, result} = create_company_with_version(@create_company_params, originator: user)

    company_count = Company.count()
    version_count = Version.count()

    company = result[:model] |> serialize
    version = result[:version] |> serialize

    assert Map.keys(result) == [:model, :version]
    assert company_count == 1
    assert version_count == 1

    assert Map.drop(company, [:id, :inserted_at, :updated_at]) == %{
             name: "Acme LLC",
             is_active: true,
             city: "Greenwich",
             website: nil,
             address: nil,
             facebook: nil,
             twitter: nil,
             founded_in: nil,
             location: %{country: "Brazil"},
             email_options: %{newsletter_enabled: false}
           }

    assert Map.drop(version, [:id, :inserted_at]) == %{
             event: "insert",
             item_type: "SimpleCompany",
             item_id: company.id,
             item_changes: company,
             originator_id: user.id,
             origin: nil,
             meta: nil
           }

    assert company == first(Company, :id) |> @repo.one |> serialize
  end

  test "creating a company with return_operation option works" do
    {:ok, company} = create_company_with_version(@create_company_params, return_operation: :model)

    company_count = Company.count()
    version_count = Version.count()

    assert company_count == 1
    assert version_count == 1

    assert company == Company |> first(:id) |> @repo.one
  end

  test "PaperTrail.insert/2 with an error returns and error tuple like Repo.insert/2" do
    result = create_company_with_version(%{name: nil, is_active: true, city: "Greenwich"})

    ecto_result =
      Company.changeset(%Company{}, %{name: nil, is_active: true, city: "Greenwich"})
      |> @repo.insert

    assert result == ecto_result
  end

  test "creating companies with insert_all/2" do
    placeholders = %{now: DateTime.to_naive(DateTime.truncate(DateTime.utc_now(), :second))}

    {:ok, %{:model => {2, nil}}} ==
      create_companies_with_version(
        [
          %{
            name: "Acme LLC",
            is_active: true,
            city: "Greenwich"
          },
          %{
            name: "Acme",
            is_active: true,
            city: "Greenwich 2"
          }
        ],
        source: Company,
        placeholders: placeholders
      )
  end

  test "updating a company with originator creates a correct company version" do
    user = create_user()
    {:ok, insert_result} = create_company_with_version()

    {:ok, result} =
      update_company_with_version(
        insert_result[:model],
        @update_company_params,
        user: user
      )

    company_count = Company.count()
    version_count = Version.count()

    company = result[:model] |> serialize
    version = result[:version] |> serialize

    assert Map.keys(result) == [:model, :version]
    assert company_count == 1
    assert version_count == 2

    assert Map.drop(company, [:id, :inserted_at, :updated_at]) == %{
             name: "Acme LLC",
             is_active: true,
             city: "Hong Kong",
             website: "http://www.acme.com",
             address: nil,
             facebook: "acme.llc",
             twitter: nil,
             founded_in: nil,
             location: %{country: "Chile"},
             email_options: %{newsletter_enabled: true}
           }

    assert Map.drop(version, [:id, :inserted_at]) == %{
             event: "update",
             item_type: "SimpleCompany",
             item_id: company.id,
             item_changes: %{
               city: "Hong Kong",
               website: "http://www.acme.com",
               facebook: "acme.llc",
               location: %{country: "Chile"},
               email_options: %{newsletter_enabled: false}
             },
             originator_id: user.id,
             origin: nil,
             meta: nil
           }

    assert company == first(Company, :id) |> @repo.one |> serialize
  end

  test "do not create version if there're no changes" do
    {:ok, insert_result} = create_company_with_version()

    {:ok, result} =
      update_company_with_version(
        insert_result[:model],
        %{}
      )

    company_count = Company.count()
    version_count = Version.count()

    company = result[:model] |> serialize
    version = result[:version]

    assert Map.keys(result) == [:model, :version]
    assert company_count == 1
    assert version_count == 1

    assert company == insert_result[:model] |> serialize
    assert version == nil
  end

  test "updating a company with originator[user] creates a correct company version" do
    user = create_user()
    {:ok, insert_result} = create_company_with_version()

    {:ok, result} =
      update_company_with_version(
        insert_result[:model],
        @update_company_params,
        user: user
      )

    company_count = Company.count()
    version_count = Version.count()

    company = result[:model] |> serialize
    version = result[:version] |> serialize

    assert Map.keys(result) == [:model, :version]
    assert company_count == 1
    assert version_count == 2

    assert Map.drop(company, [:id, :inserted_at, :updated_at]) == %{
             name: "Acme LLC",
             is_active: true,
             city: "Hong Kong",
             website: "http://www.acme.com",
             address: nil,
             facebook: "acme.llc",
             twitter: nil,
             founded_in: nil,
             location: %{country: "Chile"},
             email_options: %{newsletter_enabled: true}
           }

    assert Map.drop(version, [:id, :inserted_at]) == %{
             event: "update",
             item_type: "SimpleCompany",
             item_id: company.id,
             item_changes: %{
               city: "Hong Kong",
               website: "http://www.acme.com",
               facebook: "acme.llc",
               location: %{country: "Chile"},
               email_options: %{newsletter_enabled: false}
             },
             originator_id: user.id,
             origin: nil,
             meta: nil
           }

    assert company == first(Company, :id) |> @repo.one |> serialize
  end

  test "PaperTrail.update/2 with an error returns and error tuple like Repo.update/2" do
    {:ok, insert_result} = create_company_with_version()
    company = insert_result[:model]

    result =
      update_company_with_version(company, %{
        name: nil,
        city: "Hong Kong",
        website: "http://www.acme.com",
        facebook: "acme.llc"
      })

    ecto_result =
      Company.changeset(company, %{
        name: nil,
        city: "Hong Kong",
        website: "http://www.acme.com",
        facebook: "acme.llc"
      })
      |> @repo.update

    assert result == ecto_result
  end

  test "deleting a company creates a company version with correct attributes" do
    user = create_user()
    {:ok, insert_result} = create_company_with_version()
    {:ok, update_result} = update_company_with_version(insert_result[:model])
    company_before_deletion = first(Company, :id) |> @repo.one |> serialize
    {:ok, result} = CustomPaperTrail.delete(update_result[:model], originator: user)

    company_count = Company.count()
    version_count = Version.count()

    company = result[:model] |> serialize
    version = result[:version] |> serialize

    assert Map.keys(result) == [:model, :version]
    assert company_count == 0
    assert version_count == 3

    assert Map.drop(company, [:id, :inserted_at, :updated_at]) == %{
             name: "Acme LLC",
             is_active: true,
             city: "Hong Kong",
             website: "http://www.acme.com",
             address: nil,
             facebook: "acme.llc",
             twitter: nil,
             founded_in: nil,
             location: %{country: "Chile"},
             email_options: %{newsletter_enabled: true}
           }

    assert Map.drop(version, [:id, :inserted_at]) == %{
             event: "delete",
             item_type: "SimpleCompany",
             item_id: company.id,
             item_changes: %{
               id: company.id,
               inserted_at: company.inserted_at,
               updated_at: company.updated_at,
               name: "Acme LLC",
               is_active: true,
               website: "http://www.acme.com",
               city: "Hong Kong",
               address: nil,
               facebook: "acme.llc",
               twitter: nil,
               founded_in: nil,
               location: %{country: "Chile"},
               email_options: %{newsletter_enabled: true}
             },
             originator_id: user.id,
             origin: nil,
             meta: nil
           }

    assert company == company_before_deletion
  end

  test "delete works with a changeset" do
    user = create_user()
    {:ok, insert_result} = create_company_with_version()
    {:ok, _update_result} = update_company_with_version(insert_result[:model])
    company_before_deletion = first(Company, :id) |> @repo.one

    changeset = Company.changeset(company_before_deletion, %{})
    {:ok, result} = CustomPaperTrail.delete(changeset, originator: user)

    company_count = Company.count()
    version_count = Version.count()

    company = result[:model] |> serialize
    version = result[:version] |> serialize

    assert Map.keys(result) == [:model, :version]
    assert company_count == 0
    assert version_count == 3

    assert Map.drop(company, [:id, :inserted_at, :updated_at]) == %{
             name: "Acme LLC",
             is_active: true,
             city: "Hong Kong",
             website: "http://www.acme.com",
             address: nil,
             facebook: "acme.llc",
             twitter: nil,
             founded_in: nil,
             location: %{country: "Chile"},
             email_options: %{newsletter_enabled: true}
           }

    assert Map.drop(version, [:id, :inserted_at]) == %{
             event: "delete",
             item_type: "SimpleCompany",
             item_id: company.id,
             item_changes: %{
               id: company.id,
               inserted_at: company.inserted_at,
               updated_at: company.updated_at,
               name: "Acme LLC",
               is_active: true,
               website: "http://www.acme.com",
               city: "Hong Kong",
               address: nil,
               facebook: "acme.llc",
               twitter: nil,
               founded_in: nil,
               location: %{country: "Chile"},
               email_options: %{newsletter_enabled: true}
             },
             originator_id: user.id,
             origin: nil,
             meta: nil
           }

    assert company == serialize(company_before_deletion)
  end

  test "PaperTrail.delete/2 with an error returns and error tuple like Repo.delete/2" do
    {:ok, insert_company_result} = create_company_with_version()

    Person.changeset(%Person{}, %{
      first_name: "Izel",
      last_name: "Nakri",
      gender: true,
      company_id: insert_company_result[:model].id
    })
    |> CustomPaperTrail.insert()

    {:error, ecto_result} = insert_company_result[:model] |> Company.changeset() |> @repo.delete

    {:error, result} =
      insert_company_result[:model] |> Company.changeset() |> CustomPaperTrail.delete()

    assert Map.drop(result, [:repo_opts]) == Map.drop(ecto_result, [:repo_opts])
  end

  test "creating a person with meta tag creates a person version with correct attributes" do
    create_company_with_version()

    {:ok, new_company_result} =
      Company.changeset(%Company{}, %{
        name: "Another Company Corp.",
        is_active: true,
        address: "Sesame street 100/3, 101010"
      })
      |> CustomPaperTrail.insert()

    {:ok, result} =
      Person.changeset(%Person{}, %{
        first_name: "Izel",
        last_name: "Nakri",
        gender: true,
        company_id: new_company_result[:model].id
      })
      |> CustomPaperTrail.insert(origin: "admin", meta: %{linkname: "izelnakri"})

    person_count = Person.count()
    version_count = Version.count()

    person = result[:model] |> serialize
    version = result[:version] |> serialize

    assert Map.keys(result) == [:model, :version]
    assert person_count == 1
    assert version_count == 3

    assert Map.drop(person, [:id, :inserted_at, :updated_at]) == %{
             first_name: "Izel",
             last_name: "Nakri",
             gender: true,
             visit_count: nil,
             birthdate: nil,
             company_id: new_company_result[:model].id
           }

    assert Map.drop(version, [:id, :inserted_at]) == %{
             event: "insert",
             item_type: "SimplePerson",
             item_id: person.id,
             item_changes: person,
             originator_id: nil,
             origin: "admin",
             meta: %{linkname: "izelnakri"}
           }

    assert person == first(Person, :id) |> @repo.one |> serialize
  end

  test "updating a person creates a person version with correct attributes" do
    {:ok, initial_company_insertion} =
      create_company_with_version(%{
        name: "Acme LLC",
        website: "http://www.acme.com"
      })

    {:ok, target_company_insertion} =
      create_company_with_version(%{
        name: "Another Company Corp.",
        is_active: true,
        address: "Sesame street 100/3, 101010"
      })

    {:ok, insert_person_result} =
      Person.changeset(%Person{}, %{
        first_name: "Izel",
        last_name: "Nakri",
        gender: true,
        company_id: target_company_insertion[:model].id
      })
      |> CustomPaperTrail.insert(origin: "admin")

    {:ok, result} =
      Person.changeset(insert_person_result[:model], %{
        first_name: "Isaac",
        visit_count: 10,
        birthdate: ~D[1992-04-01],
        company_id: initial_company_insertion[:model].id
      })
      |> CustomPaperTrail.update(origin: "scraper", meta: %{linkname: "izelnakri"})

    person_count = Person.count()
    version_count = Version.count()

    person = result[:model] |> serialize
    version = result[:version] |> serialize

    assert Map.keys(result) == [:model, :version]
    assert person_count == 1
    assert version_count == 4

    assert Map.drop(person, [:id, :inserted_at, :updated_at]) == %{
             company_id: initial_company_insertion[:model].id,
             first_name: "Isaac",
             visit_count: 10,
             birthdate: ~D[1992-04-01],
             last_name: "Nakri",
             gender: true
           }

    assert Map.drop(version, [:id, :inserted_at]) == %{
             event: "update",
             item_type: "SimplePerson",
             item_id: person.id,
             item_changes: %{
               first_name: "Isaac",
               visit_count: 10,
               birthdate: ~D[1992-04-01],
               company_id: initial_company_insertion[:model].id
             },
             originator_id: nil,
             origin: "scraper",
             meta: %{linkname: "izelnakri"}
           }

    assert person == first(Person, :id) |> @repo.one |> serialize
  end

  test "deleting a person creates a person version with correct attributes" do
    create_company_with_version(%{name: "Acme LLC", website: "http://www.acme.com"})

    {:ok, target_company_insertion} =
      create_company_with_version(%{
        name: "Another Company Corp.",
        is_active: true,
        address: "Sesame street 100/3, 101010"
      })

    # add link name later on
    {:ok, insert_person_result} =
      Person.changeset(%Person{}, %{
        first_name: "Izel",
        last_name: "Nakri",
        gender: true,
        company_id: target_company_insertion[:model].id
      })
      |> CustomPaperTrail.insert(origin: "admin")

    {:ok, update_result} =
      Person.changeset(insert_person_result[:model], %{
        first_name: "Isaac",
        visit_count: 10,
        birthdate: ~D[1992-04-01],
        company_id: target_company_insertion[:model].id
      })
      |> CustomPaperTrail.update(origin: "scraper", meta: %{linkname: "izelnakri"})

    person_before_deletion = first(Person, :id) |> @repo.one |> serialize

    {:ok, result} =
      CustomPaperTrail.delete(
        update_result[:model],
        origin: "admin",
        meta: %{linkname: "izelnakri"}
      )

    person_count = Person.count()
    version_count = Version.count()

    assert Map.keys(result) == [:model, :version]
    old_person = update_result[:model] |> serialize
    version = result[:version] |> serialize

    assert person_count == 0
    assert version_count == 5

    assert Map.drop(version, [:id, :inserted_at]) == %{
             event: "delete",
             item_type: "SimplePerson",
             item_id: old_person.id,
             item_changes: %{
               id: old_person.id,
               inserted_at: old_person.inserted_at,
               updated_at: old_person.updated_at,
               first_name: "Isaac",
               last_name: "Nakri",
               gender: true,
               visit_count: 10,
               birthdate: ~D[1992-04-01],
               company_id: target_company_insertion[:model].id
             },
             originator_id: nil,
             origin: "admin",
             meta: %{linkname: "izelnakri"}
           }

    assert old_person == person_before_deletion
  end

  test "inserting, updating and deleting a company with model_key option works" do
    {:ok,
     %{
       insert_model: %Company{} = insert_model,
       insert_version: %Version{} = insert_version
     }} =
      create_company_with_version(
        @create_company_params,
        model_key: :insert_model,
        version_key: :insert_version
      )

    assert insert_model == Company |> first(:id) |> @repo.one
    assert insert_version.id == Version |> first(:id) |> @repo.one |> Map.get(:id)

    {:ok,
     %{
       update_model: %Company{} = update_model,
       update_version: %Version{} = update_version
     }} =
      update_company_with_version(
        insert_model,
        @update_company_params,
        model_key: :update_model,
        version_key: :update_version
      )

    assert update_model == Company |> last(:id) |> @repo.one
    assert update_version.id == Version |> last(:id) |> @repo.one |> Map.get(:id)

    {:ok,
     %{
       delete_model: %Company{} = delete_model,
       delete_version: %Version{} = delete_version
     }} =
      CustomPaperTrail.delete(
        update_model,
        model_key: :delete_model,
        version_key: :delete_version
      )

    assert delete_model != Company |> last(:id) |> @repo.one
    assert delete_version.id == Version |> last(:id) |> @repo.one |> Map.get(:id)
  end

  test "update_all updates persons and creates versions with correct attributes" do
    user1 = create_user()
    %{id: user2_id} = user2 = create_user()
    %{id: user3_id} = user3 = create_user()
    ids = [user2.id, user3.id]
    new_username = "isaac"

    assert user1.username !== new_username
    assert user2.username !== new_username
    assert user3.username !== new_username

    %{model: {2, nil}, version: {2, nil}} =
      User
      |> where([p], p.id in ^ids)
      |> CustomPaperTrail.update_all(set: [username: new_username])

    assert @repo.get(User, user1.id).username === user1.username
    assert @repo.get(User, user2.id).username === new_username
    assert @repo.get(User, user3.id).username === new_username

    assert [
             %PaperTrail.Version{
               item_id: ^user2_id,
               item_changes: %{"username" => ^new_username}
             }
           ] = PaperTrail.VersionQueries.get_versions(User, user2.id)

    assert [
             %PaperTrail.Version{
               item_id: ^user3_id,
               item_changes: %{"username" => ^new_username}
             }
           ] = PaperTrail.VersionQueries.get_versions(User, user3.id)
  end

  test "update_all should insert versions before updating" do
    {:ok, %{model: company}} = create_company_with_version()

    %{model: {1, nil}, version: {1, nil}} =
      Company
      |> where([c], c.is_active)
      |> CustomPaperTrail.update_all(set: [is_active: false])

    assert %Company{is_active: false} = @repo.get(Company, company.id)

    company_id = company.id

    assert [
             %PaperTrail.Version{
               item_id: ^company_id,
               event: "update",
               item_changes: %{"is_active" => false}
             },
             %PaperTrail.Version{
               item_id: ^company_id,
               event: "insert"
             }
           ] = PaperTrail.VersionQueries.get_versions(Company, company.id)
  end

  test "update_all with returning option returns inserted version" do
    create_user()
    %{id: user2_id} = create_user()
    %{id: user3_id} = create_user()
    ids = [user2_id, user3_id]
    new_username = "isaac"

    {2, [%PaperTrail.Version{item_id: ^user2_id}, %PaperTrail.Version{item_id: ^user3_id}]} =
      User
      |> where([p], p.id in ^ids)
      |> CustomPaperTrail.update_all(
        [set: [username: new_username]],
        returning: true,
        return_operation: :version
      )
  end

  test "creating a person and associated company creates a person version with correct attributes" do
    {:ok, result} =
      Person.with_company_changeset(%Person{}, %{
        first_name: "Izel",
        last_name: "Nakri",
        gender: true,
        company: %{
          name: "My company"
        }
      })
      |> CustomPaperTrail.insert(origin: "admin", meta: %{linkname: "izelnakri"})

    person_count = Person.count()
    version_count = Version.count()

    person = result[:model] |> serialize
    company = result[:model].company |> serialize
    version = result[:version] |> serialize

    assert Map.keys(result) == [:model, :version]
    assert person_count == 1
    assert version_count == 1

    Map.drop(person, [:id, :inserted_at, :updated_at])

    assert Map.drop(person, [:id, :inserted_at, :updated_at]) == %{
             first_name: "Izel",
             last_name: "Nakri",
             gender: true,
             visit_count: nil,
             birthdate: nil,
             company_id: result[:model].company.id,
             company: %{
               "changes" => company,
               "event" => "insert"
             }
           }

    assert %{name: "My company"} = company

    assert Map.drop(version, [:id, :inserted_at]) == %{
             event: "insert",
             item_type: "SimplePerson",
             item_id: person.id,
             item_changes: person,
             originator_id: nil,
             origin: "admin",
             meta: %{linkname: "izelnakri"}
           }
  end

  test "updating a person and associated company creates a person version with correct attributes" do
    {:ok, insert_person_result} =
      Person.with_company_changeset(%Person{}, %{
        first_name: "Izel",
        last_name: "Nakri",
        gender: true,
        company: %{
          name: "My company"
        }
      })
      |> CustomPaperTrail.insert(origin: "admin")

    {:ok, result} =
      Person.with_company_changeset(insert_person_result[:model], %{
        first_name: "Isaac",
        visit_count: 10,
        birthdate: ~D[1992-04-01],
        company: %{
          name: "Other company"
        }
      })
      |> CustomPaperTrail.update(origin: "scraper", meta: %{linkname: "izelnakri"})

    assert insert_person_result[:model].company_id == result[:model].company_id

    person_count = Person.count()
    version_count = Version.count()

    person = result[:model] |> serialize
    company = result[:model].company |> serialize
    version = result[:version] |> serialize

    assert Map.keys(result) == [:model, :version]
    assert person_count == 1
    assert version_count == 2

    assert Map.drop(person, [:id, :inserted_at, :updated_at]) == %{
             birthdate: ~D[1992-04-01],
             company: %{
               "changes" => company,
               "event" => "insert"
             },
             company_id: company.id,
             first_name: "Isaac",
             gender: true,
             last_name: "Nakri",
             visit_count: 10
           }

    assert Map.drop(version, [:id, :inserted_at]) == %{
             event: "update",
             item_type: "SimplePerson",
             item_id: person.id,
             item_changes: %{
               first_name: "Isaac",
               visit_count: 10,
               birthdate: ~D[1992-04-01],
               company: %{changes: %{name: "Other company"}, event: :update}
             },
             originator_id: nil,
             origin: "scraper",
             meta: %{linkname: "izelnakri"}
           }
  end

  defp create_user do
    User.changeset(%User{}, %{token: "fake-token", username: "izelnakri"}) |> @repo.insert!
  end

  defp create_company_with_version(params \\ @create_company_params, options \\ []) do
    Company.changeset(%Company{}, params) |> CustomPaperTrail.insert(options)
  end

  defp create_companies_with_version(params, options) do
    params
    |> Enum.map(&Company.changeset(%Company{}, &1))
    |> Enum.map(fn %{changes: changes} ->
      changes
      |> Map.put(:inserted_at, {:placeholder, :now})
      |> Map.put(:updated_at, {:placeholder, :now})
    end)
    |> CustomPaperTrail.insert_all(options)
  end

  defp update_company_with_version(company, params \\ @update_company_params, options \\ []) do
    Company.changeset(company, params) |> CustomPaperTrail.update(options)
  end

  defp serialize(data), do: Serializer.serialize(data, repo: PaperTrail.Repo)
end
