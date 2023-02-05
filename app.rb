require "sinatra"
require "sinatra/content_for"
require "tilt/erubis"
require "webrick"
require "pg"
require "pry-byebug"
require "stamp"
require "securerandom"

require_relative "database_persistence"

configure do
  enable :sessions
  set :session_secret, Sinatra::Base.production? ? SecureRandom.hex(64) : 'secret'
  set :erb, :escape_html => true
end

configure(:development) do
  require "sinatra/reloader"
end

helpers do
  def print_active_task(task)
    timestamp = task["start"]
    time = timestamp.stamp("01:00 AM")
    date = timestamp.stamp("Jan 5 2023")

    "You are currently working on <em>#{task["task"]}</em> since #{time} of #{date}"
  end

  def normalize_date_time(time)
    string = time.to_s
    string.split(' ')[0..1].join('T')
  end

  def paginate_items(items, page, reverse: nil)
    first = (page - 1) * 10
    last =  (page * 10)
  
    if reverse
      items.reverse[first...last].each { |item| yield item }
    else
      items[first...last].each { |item| yield item }
    end
  end
end

def page_details(page, size)
  page = page == '' ? 1 : page.to_i
  page_count = (size / 10.0).ceil
  page = 1 if page < 1
  page = page_count if page > page_count
  [page, page_count]
end

before do
  @storage = TimeTracker.new
  session[:user] ||= {}
end

get "/" do
  @recent_tasks = @storage.all_tasks
  erb :index
end

get "/timer" do
  @tasks = @storage.existing_tasks
  @projects = @storage.existing_projects
  @clients = @storage.existing_clients
  @active_task = @storage.active_task
  @recent_tasks = @storage.all_tasks

  erb :timer
end

post "/timer" do
  if @storage.active_task
    @storage.stop_task
    redirect "/timer"
  else
    task = params["task"].strip
    project = params["project"].strip.empty? ? nil : params["project"].strip
    client = params["client"].strip.empty? ? nil : params["client"].strip

    error = @storage.validate_inputs(task, project, client)
    if error
      session[:error] = error
      redirect "/timer"
    else
      @storage.start_task(client, project, task)
      redirect "/timer"
    end
  end
end

get "/edit/task/:id" do
  field = params["field"]
  id = params["id"]
  @task = @storage.current_task(id)

  erb :edit
end

post "/edit/task/:id" do
  id = params["id"]
  task = params["task"]
  start = params["start"]
  stop = params["stop"]
  project = params["project"] == '' ? nil : params["project"]
  client = params["client"] == '' ? nil : params["client"]
  @task = @storage.current_task(id)

  error = @storage.validate_inputs(task, project, client, start, stop)

  if error
    session[:error] = error
    status 422
    erb :edit
  else
    @storage.edit_task(id, task, start, stop, project, client)
    redirect "/timer"
  end
end

# Must have filter options above the table
get "/tasks/all/:page" do
  @tasks = @storage.all_tasks
  @page, @page_count = page_details(params["page"], @tasks.size)
  @current_path = request.fullpath

  erb :tasks
end

# Display all projects 
get "/projects/all/:page" do
  @projects = @storage.all_projects
  @page, @page_count = page_details(params["page"], @projects.size)
  @current_path = request.fullpath

  erb :projects
end

get "/edit/project/:id" do
  project_id = params["id"]
  @project = @storage.current_project(project_id)

  erb :edit_project
end

post "/edit/project/:id" do
  project_id = params["id"]
  project = params["project"].strip
  client = params["client"].strip
  @project = @storage.current_project(project_id)

  if project.empty?
    session[:error] = "Please enter a valid project name"
    status 422
    erb :edit_project
  else
    @storage.update_project(project_id, project, client)
    redirect "/projects/all/1"
  end
end

get "/clients/all/:page" do
  @clients = @storage.existing_clients
  @page, @page_count = page_details(params["page"], @clients.size)
  @current_path = request.fullpath

  erb :clients
end

get "/edit/client/:id" do
  client_id = params["id"]
  @client = @storage.current_client(client_id)

  erb :edit_client
end

post "/edit/client/:id" do
  client_id = params["id"]
  client = params["client"].strip
  @client = @storage.current_client(client_id)

  if client.empty?
    session[:error] = "Please enter a valid name for client"
    status 422
    erb :edit_client
  else
    error = @storage.update_client(client_id, client)
    if error
      session[:error] = error
      erb :edit_client
    else
      redirect "/clients/all/1"
    end
  end
end

post "/client/delete" do
  client_id = params["client_id"]
  @storage.delete_client(client_id)

  redirect params["url"]
end

post "/task/delete" do
  task_id = params["task_id"]
  @storage.delete_task(task_id)

  redirect params["url"]
end


post "/task" do

end
