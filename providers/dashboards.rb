action :create do
  require 'json'
  require 'faraday'
  require 'faraday/conductivity'

  Chef::Application.fatal!("You need to set an access token in order to use the API.") if node[:graylog2][:rest][:admin_access_token].nil?

  rest_uri = node[:graylog2][:rest][:listen_uri] || "http://#{node['ipaddress']}:12900/"
  connection = Faraday.new(url: rest_uri) do |faraday|
    faraday.basic_auth(node[:graylog2][:rest][:admin_access_token], 'token')
    faraday.adapter(Faraday.default_adapter)
    faraday.use :repeater, retries: 5, mode: :one
  end
 
  if new_resource.dashboard
    dashboards = [new_resource.dashboard]
  else
    dashboards = node[:graylog2][:dashboards]
  end

  if not dashboards.nil?
    dashboards.each do |dashboard|
      parsed_dashboard = JSON.parse(dashboard)
      response = connection.get('/dashboards')

      if response.success?
        parsed_response = JSON.parse(response.body)
        saved_dashboards = parsed_response.fetch("dashboards")
        if existent_dashboard?(saved_dashboards, parsed_dashboard)
          break
        end
      end

      if new_resource.widgets
        widgets = JSON.parse(new_resource.widgets)
      else
        widgets = parsed_dashboard['widgets']
        parsed_dashboard.delete('widgets')
      end
      Chef::Application.fatal!("You need to set dashboard widgets in order to create a dashboard") if widgets.nil?

      dashboard_id = create_dashboard(connection, parsed_dashboard)

      widgets.each do |widget|
        create_dashboard_widget(connection, dashboard_id, widget)
      end
    end
  end
end

def create_dashboard(connection, data)
  begin
    response = connection.post('/dashboards', data.to_json, { :'Content-Type' => 'application/json' })
    dashboard_id = JSON.parse(response.body).fetch('dashboard_id')
    Chef::Log.debug("Graylog2 API response: #{response.status}")
  rescue Exception
    Chef::Application.fatal!("Failed to create dashboard #{parsed_dashboard.fetch('title')}.")
  end
    
  return dashboard_id
end

def create_dashboard_widget(connection, dashboard_id, data)
  response = connection.post("/dashboards/#{dashboard_id}/widgets", data.to_json, { :'Content-Type' => 'application/json' })
  Chef::Log.info("Graylog2 API response: #{response.status}")

  return response
end

def existent_dashboard?(saved_dashboards, dashboard)
  saved_dashboards.each do |saved_dashboard|
    if saved_dashboard.fetch("title") == dashboard.fetch("title")
      return true
    end
  end

  return false
end
