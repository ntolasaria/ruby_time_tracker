require "sinatra"
require "sinatra/reloader"
require "sinatra/content_for"
require "tilt/erubis"
require "webrick"
require "pg"
require "pry-byebug"
require "stamp"

enable :sessions

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
end

class TimeTracker
  def initialize
    @connection = PG.connect(dbname: "time_tracker")
  end

  def query(sql, *params)
    @connection.exec_params(sql, params)
  end

  def all_tasks
    sql =<<~SQL
    SELECT  tasks.name AS "task", tasks.id AS "task_id", projects.name AS "project", projects.id AS "project_id", clients.name AS "client",
            clients.id AS "client_id", tasks.start_time AS "start", tasks.stop_time AS "stop", (tasks.stop_time - tasks.start_time) AS "duration"
    FROM tasks
    LEFT OUTER JOIN projects
    ON tasks.project_id = projects.id
    LEFT OUTER JOIN clients
    ON projects.client_id = clients.id
    WHERE tasks.stop_time IS NOT NULL
    ORDER BY tasks.start_time DESC;
    SQL

    result = query(sql)

    result_to_list_hash(result)
  end

  def to_time(string)
    time = string.split(/[- :T]/).map(& :to_i)
    Time.new(*time)
  end

  def existing_clients
    sql = "SELECT name, id FROM clients;"
    result = query(sql)

    result_to_list_hash(result)
  end

  def existing_projects
    sql =<<~SQL
      SELECT DISTINCT(name), id FROM projects;
    SQL

    result = query(sql)
    result_to_list_hash(result)
  end

  def existing_tasks
    sql = "SELECT DISTINCT(name) FROM tasks;"
    result = query(sql)
    result_to_list_hash(result)
  end

  def current_client(client_id)
    sql =<<~SQL
      SELECT * FROM clients WHERE id = $1;
    SQL

    result = query(sql, client_id)
    result_to_list_hash(result)
  end

  def current_project(project_id)
    sql =<<~SQL
      SELECT id, name FROM projects WHERE id = $1;
    SQL

    result = query(sql, project_id)

    result_to_list_hash(result)
  end


  def create_project_and_return_id(client_id, project)
    sql =<<~SQL
      INSERT INTO projects (name, client_id)
      VALUES ($1, $2)
      RETURNING id;
    SQL

    result = query(sql, project, client_id)
    result.first["id"]
  end

  def generate_or_retrieve_project_id(client_id, project)
    project_id = nil

    if client_id
      sql =<<~SQL
        SELECT id, client_id 
        FROM projects WHERE name = $1 AND client_id = $2;
      SQL
      result = query(sql, project, client_id)
    else
      sql =<<~SQL
        SELECT id, client_id
        FROM projects
        WHERE name = $1 AND client_id IS NULL;
      SQL
      result = query(sql, project)
    end

    if result.ntuples == 0
      project_id = create_project_and_return_id(client_id, project)
      return project_id
    elsif client_id
      result.each do |tuple|
        return tuple["id"] if client_id == tuple["client_id"]
      end

      project_id = create_project_and_return_id(client_id, project)
      return project_id
    else
      return result.first["id"]
    end
  end

  def generate_or_retrieve_client_id(client)
    sql_client = "SELECT * FROM clients WHERE name = $1;"
    client_result = query(sql_client, client)

    if client_result.ntuples == 0
      sql_insert = "INSERT INTO clients (name) VALUES ($1);"
      query(sql_insert, client)
    end

    client_result = query(sql_client, client)
    client_id = client_result.first["id"]
  end

  def create_client_return_id(name)
    sql = "INSERT INTO clients (name) VALUES ($1);"
    query(sql, name)
    sql = "SELECT id FROM clients WHERE name = $1;"
    result = query(sql, name)
    result.first["id"].to_i
  end

  def active_task
    sql =<<~SQL
      SELECT tasks.name AS "task", tasks.start_time AS "start", projects.name AS "project", clients.name AS "client" 
      FROM tasks
      LEFT OUTER JOIN projects
      ON tasks.project_id = projects.id
      LEFT OUTER JOIN clients
      ON projects.client_id = clients.id
      WHERE tasks.start_time IS NOT NULL AND tasks.stop_time IS NULL;
    SQL

    result = query(sql)

    if result.ntuples == 0
      nil
    else
      result_to_list_hash(result).first
    end
  end

  def stop_task
    sql =<<~SQL
      UPDATE tasks
      SET stop_time = NOW()
      WHERE start_time IS NOT NULL AND stop_time IS NULL;
    SQL
    query(sql)
  end

  def start_task(client, project, task)
    client_id = nil
    project_id = nil

    client_id = generate_or_retrieve_client_id(client) if client
    project_id = generate_or_retrieve_project_id(client_id, project) if project

    sql =<<~SQL
      INSERT INTO tasks (name, project_id, start_time)
      VALUES ($1, $2, $3);
    SQL

    query(sql, task, project_id, 'NOW()')
  end

  def current_task(task_id)
    sql =<<~SQL
      SELECT tasks.name AS "task", tasks.start_time AS "start", tasks.stop_time AS "stop",
      projects.name AS "project", clients.name AS "client"
      FROM tasks
      LEFT OUTER JOIN projects
      ON tasks.project_id = projects.id
      LEFT OUTER JOIN clients
      ON projects.client_id = clients.id
      WHERE tasks.id = $1;
    SQL

    result = query(sql, task_id)

    result_to_list_hash(result).first
  end

  def edit_task(id, task, start, stop, project, client)
    client_id = nil
    project_id = nil

    client_id = generate_or_retrieve_client_id(client) if client
    project_id = generate_or_retrieve_project_id(client_id, project) if project

    sql =<<~SQL
      UPDATE tasks
      SET name = $1, start_time = $2, stop_time = $3, project_id = $4
      WHERE id = $5;
    SQL

    query(sql, task, start, stop, project_id, id)
  end

  def validate_inputs(task, project, client, start=nil, stop=nil)
    start = to_time(start) if start
    stop = to_time(stop) if stop

    if (start && stop) && start >= stop
      "Start time should be before the stop time"
    elsif task.empty?
      "Please enter a valid task name"
    elsif client && !project
      "There must be a project associated with the task and client"
    else
      nil
    end
  end

  def delete_task(task_id)
    sql =<<~SQL
      DELETE FROM tasks WHERE id = $1;
    SQL

    query(sql, task_id)
  end

  def result_to_list_hash(result)
    result.to_a.map do |hash|
      hash["start"] = to_time(hash["start"]) if hash["start"]
      hash["stop"] = to_time(hash["stop"]) if hash["stop"]
      hash
    end
  end
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

def paginate_items(items, page, reverse: nil)
  first = (page - 1) * 10
  last =  (page * 10)

  if reverse
    items.reverse[first...last].each { |item| yield item }
  else
    items[first...last].each { |item| yield item }
  end
end

def page_details(page, size)
  page = page == '' ? 1 : page.to_i
  page_count = (size / 10.0).ceil
  page = 1 if page < 1
  page = page_count if page > page_count
  [page, page_count]
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
  @projects = @storage.existing_projects
end

get "/clients/all/:page" do
  @clients = @storage.existing_clients
  @page, @page_count = page_details(params["page"], @clients.size)

  erb :clients
end

post "/task/delete" do
  task_id = params["task_id"]
  @storage.delete_task(task_id)

  redirect params["url"]
end


post "/task" do
end
