defmodule BlennyExampleApp.Blenny.FormAuthTest do
  use BlennyExampleAppWeb.ConnCase, async: false

  @moduledoc """
  Tests for the FormAuth module.

  Uses `async: false` because the InMemory store and AuthRegistry use
  named ETS tables which are global across tests.
  """

  setup do
    # Clear InMemory store ETS tables between tests
    for table <- [:blenny_storage_in_memory, :blenny_storage_in_memory_uname] do
      if :ets.info(table) != :undefined do
        :ets.delete_all_objects(table)
      end
    end

    :ok
  end

  describe "Crypto.derive_key/2" do
    test "returns a 64-character hex string" do
      hash = BlennyExampleApp.Blenny.FormAuth.Crypto.derive_key("password", "salt")
      assert String.match?(hash, ~r/^[0-9a-f]{64}$/)
    end

    test "same inputs produce same hash" do
      a = BlennyExampleApp.Blenny.FormAuth.Crypto.derive_key("hello", "world")
      b = BlennyExampleApp.Blenny.FormAuth.Crypto.derive_key("hello", "world")
      assert a == b
    end

    test "different passwords produce different hashes" do
      a = BlennyExampleApp.Blenny.FormAuth.Crypto.derive_key("password1", "salt")
      b = BlennyExampleApp.Blenny.FormAuth.Crypto.derive_key("password2", "salt")
      assert a != b
    end
  end

  describe "GET /auth/signin" do
    test "renders sign-in form", %{conn: conn} do
      conn = get(conn, ~p"/auth/signin")
      assert html_response(conn, 200) =~ "Sign In"
      assert html_response(conn, 200) =~ "Create an account"
    end
  end

  describe "GET /auth/register" do
    test "renders registration form", %{conn: conn} do
      conn = get(conn, ~p"/auth/register")
      assert html_response(conn, 200) =~ "Register"
      assert html_response(conn, 200) =~ "Already have an account"
    end
  end

  describe "POST /auth/register" do
    test "registers a new user and redirects", %{conn: conn} do
      conn =
        post(conn, ~p"/auth/register", %{
          "username" => "testuser",
          "password" => "password123",
          "display_name" => "Test User"
        })

      assert redirected_to(conn, 302) =~ "/dashboard"
      assert get_session(conn, "blenny_user_id")
      assert get_session(conn, "blenny_user_role") == "user"
    end

    test "rejects short password", %{conn: conn} do
      conn =
        post(conn, ~p"/auth/register", %{
          "username" => "testuser2",
          "password" => "short",
          "display_name" => "Test"
        })

      assert html_response(conn, 200) =~ "at least 8 characters"
    end

    test "rejects empty username", %{conn: conn} do
      conn =
        post(conn, ~p"/auth/register", %{
          "username" => "",
          "password" => "password123",
          "display_name" => "Test"
        })

      assert html_response(conn, 200) =~ "required"
    end

    test "rejects duplicate username", %{conn: conn} do
      post(conn, ~p"/auth/register", %{
        "username" => "dupuser",
        "password" => "password123",
        "display_name" => "First"
      })

      conn =
        post(conn, ~p"/auth/register", %{
          "username" => "dupuser",
          "password" => "password123",
          "display_name" => "Second"
        })

      assert html_response(conn, 200) =~ "already taken"
    end
  end

  describe "POST /auth/signin" do
    test "signs in with valid credentials and redirects", %{conn: conn} do
      post(conn, ~p"/auth/register", %{
        "username" => "signinuser",
        "password" => "password123",
        "display_name" => "Sign In User"
      })

      conn =
        post(conn, ~p"/auth/signin", %{
          "username" => "signinuser",
          "password" => "password123"
        })

      assert redirected_to(conn, 302) =~ "/dashboard"
      assert get_session(conn, "blenny_user_id")
      assert get_session(conn, "blenny_user_role") == "user"
    end

    test "rejects wrong password", %{conn: conn} do
      post(conn, ~p"/auth/register", %{
        "username" => "wrongpw",
        "password" => "password123",
        "display_name" => "Wrong PW"
      })

      conn =
        post(conn, ~p"/auth/signin", %{
          "username" => "wrongpw",
          "password" => "wrongpass"
        })

      assert html_response(conn, 200) =~ "Invalid"
    end

    test "rejects unknown username", %{conn: conn} do
      conn =
        post(conn, ~p"/auth/signin", %{
          "username" => "nobody",
          "password" => "password123"
        })

      assert html_response(conn, 200) =~ "Invalid"
    end
  end

  describe "POST /auth/signout" do
    test "drops session and redirects", %{conn: conn} do
      post(conn, ~p"/auth/register", %{
        "username" => "signoutuser",
        "password" => "password123",
        "display_name" => "Sign Out"
      })

      conn =
        post(conn, ~p"/auth/signin", %{
          "username" => "signoutuser",
          "password" => "password123"
        })

      assert get_session(conn, "blenny_user_id")

      conn = post(conn, ~p"/auth/signout", %{})
      assert redirected_to(conn, 302) =~ "/"
      # Session is set for drop — cookie is cleared in response headers
      assert conn.private[:plug_session_info] == :drop
    end
  end
end
