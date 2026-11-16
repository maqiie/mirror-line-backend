# Lets the React dashboard call the API from an explicitly allowed origin.
# The EAs are not browsers and are unaffected by CORS.
default_origins = if Rails.env.production?
  []
else
  ["http://localhost:5173", "http://localhost:3001"]
end

dashboard_origins = ENV.fetch("DASHBOARD_ORIGINS", "").split(",")
  .map(&:strip)
  .reject(&:blank?)

allowed_origins = dashboard_origins.presence || default_origins

if Rails.env.production? && allowed_origins.empty?
  raise "DASHBOARD_ORIGINS must be configured in production"
end

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*allowed_origins)
    resource "/api/*",
             headers: :any,
             methods: %i[get post put patch delete options head],
             max_age: 600
  end
end
