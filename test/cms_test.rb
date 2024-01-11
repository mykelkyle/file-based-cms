ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "minitest/reporters"
require "rack/test"
require "fileutils"
Minitest::Reporters.use!

require_relative "../cms"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content="")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => {username: "admin" } }
  end

  def app
    Sinatra::Application
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"

    get "/"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
  end

  def test_viewing_text_document
    create_document "history.txt", "Ruby 0.95 released"
    get "/history.txt"

    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "Ruby 0.95 released"
  end

  def test_document_not_found
    get "/notafile.ext" #Attempt to access a nonexistent file

    assert_equal 302, last_response.status
    assert_includes session[:message], "notafile.ext does not exist"
  end

  def test_viewing_markdown_document
    create_document "about.md", "# Ruby is..."
    get "/about.md"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end

  def test_editing_document
    create_document "history.txt"

    get "/history.txt/edit", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, '<button type="submit"'
  end

  def test_editing_document_signed_out
    create_document "history.txt"

    get "/history.txt/edit"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_updating_document
    post "/history.txt", {content: "new content"}, admin_session

    assert_equal 302, last_response.status
    assert_includes session[:message], "history.txt has been updated"

    get "/history.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_updating_document_signed_out
    post "/history.txt", {content: "new content"}

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_view_new_document_form
    get "/new", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, '<button type="submit"'
  end

  def test_view_new_document_form_signed_out
    get "/new"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_create_new_document
    post "/create", {filename: "test.txt"}, admin_session
    assert_equal 302, last_response.status
    assert_includes session[:message], "test.txt was created"

    get "/"
    assert_includes last_response.body, "test.txt"
  end

  def test_create_new_document_signed_out
    post "/create", {filename: "test.txt"}

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_create_new_document_with_invalid_filename
    post "/create", {filename: ""}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required"

    post "/create", filename: "test.invalidext"
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Invalid file extension"
  end

  def test_delete_document
    create_document "test.txt"
    post "/test.txt/delete", {}, admin_session

    assert_equal 302, last_response.status
    assert_includes session[:message], "test.txt has been deleted"

    get "/"
    refute_includes last_response.body, 'href="/test.txt"'
  end

  def test_delete_document_signed_out
    create_document "test.txt"
    post "/test.txt/delete"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_signin_form
    get "/users/signin"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, '<button type="submit"'
  end

  def test_signin
    post "/users/signin", username: "admin", password: "password"

    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:username]

    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin"
  end

  def test_signin_with_bad_credentials
    post "/users/signin", username: "fakeuser", password: "fakepassword"

    assert_equal 422, last_response.status
    assert_nil session[:username]
    assert_includes last_response.body, "Invalid credentials."
  end

  def test_signout
    get "/", {}, {"rack.session" => {username: "admin"}}
    assert_includes last_response.body, "Signed in as admin"

    post "/users/signout"
    assert_includes "You have been signed out.", session[:message]

    get last_response["Location"]
    assert_nil session[:username]
    assert_includes last_response.body, "Sign In"
  end
end
