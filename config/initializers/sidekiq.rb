redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

Sidekiq.configure_client { |config| config.redis = redis }

Sidekiq.configure_server do |config|
  config.redis = redis
  config.on(:startup) do
    Sidekiq::Cron::Job.load_from_hash(
      "expire_stale_commands" => {
        "cron"  => "* * * * *",
        "class" => "ExpireStaleCommandsJob"
      }
    )
  end
end
