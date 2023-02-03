# Time traker app - inspired by toggl track 

- single user for now
- database connected
- client
  - project
    - specific task
      - start time and stop time
      - time records

- sinatra based project backed by postgres

- basic routes 
  - / 
    - displays a basic snapshot of client and projects and total time spent
    - also displays if any job is running presently
    - button / link to "/timer"
  - /timer
    - display options to client, project and task
    - if not existing, create fresh record in database
    - button to start / stop timer. Toggle the state of the button based on timer running or not
    - when a task is started - display the start time and date

  - /projects
    - detailed view of entries with respect to projects

  - /client
    - detailed view of entries with respect to a client

  - /reports
    - view of time spent based on time frames by user
    - give various options as well as a custom calendar option


 
