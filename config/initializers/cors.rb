# Lets the React dashboard call the dashboard endpoints from another origin.
# The EAs are not browsers and are unaffected by CORS.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("DASHBOARD_ORIGINS", "http://localhost:5173,http://localhost:3001").split(",")
    resource "/api/*",
             headers: :any,
             methods: %i[get post put patch delete options head],
             max_age: 600
  end
end
