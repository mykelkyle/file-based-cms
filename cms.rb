require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"
require "pry"

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_content(path)
  content = File.read(path)
  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    erb render_markdown(content)
  end
end

def load_user_credentials
  credentials_path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
  YAML.load_file(credentials_path)
end

def create_document(name, content="")
  File.open(File.join(data_path, name), "w") do |file|
    file.write(content)
  end
end

def valid_filename?(file)
  file.split(".")[1] == "md" || file.split(".")[1] == "txt"
end

def signed_in?
  session[:username]
end

def redirect_user
  session[:message] = "You must be signed in to do that."
  redirect "/"
end

def valid_credentials?(username, password)
  credentials = load_user_credentials

  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username])
    bcrypt_password == password
  else
    false
  end
end

get "/" do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end

  erb :index
end

get "/new" do
  redirect_user if !signed_in?
  erb :new
end

post "/create" do
  redirect_user if !signed_in?
  filename = params[:filename]

  if filename.size == 0
    session[:message] = "A name is required."
    status 422
    erb :new
  elsif !valid_filename?(filename)
    session[:message] = "Invalid file extension. (md/txt)"
    status 422
    erb :new
  else
    create_document(filename)
    session[:message] = "#{filename} was created."
    redirect "/"
  end
end

post "/:filename" do
  redirect_user if !signed_in?
  file_path = File.join(data_path, params[:filename])

  File.write(file_path, params[:content])

  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end


get "/:filename" do
  file_path = File.join(data_path, params[:filename])

  if File.file?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

get "/:filename/edit" do
  redirect_user if !signed_in?
  file_path = File.join(data_path, params[:filename])

  @filename = params[:filename]
  @content = File.read(file_path)

  erb :edit
end

post "/:filename/delete" do
  redirect_user if !signed_in?
  file_path = File.join(data_path, params[:filename])

  File.delete(file_path)
  session[:message] = "#{params[:filename]} has been deleted."
  redirect "/"
end

get "/users/signin" do
  erb :signin
end

post "/users/signin" do
  username = params[:username]

  if valid_credentials?(username, params[:password])
    session[:username] = username
    session[:message] = "Welcome!"
    redirect "/"
  else
    session[:message] = "Invalid credentials."
    status 422
    erb :signin
  end
end

post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end
