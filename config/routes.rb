Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # ---------- EA-facing (header: X-Account-Token) ----------
      scope module: :ea do
        post "events",           to: "events#create"
        post "heartbeat",        to: "heartbeats#create"
        get  "commands/pending", to: "commands#pending"
        post "commands/:id/ack", to: "commands#ack"
      end

      # ---------- Dashboard (Mirrorline) - header: Authorization: Bearer <token> ----------
      post "session",   to: "auth#login"
      delete "session", to: "auth#logout"
      post "auth/login", to: "auth#login"
      post "auth/register", to: "auth#register"
      get  "auth/verify-email", to: "auth#verify_email"
      post "auth/verification/resend", to: "auth#resend_verification"
      post "auth/refresh", to: "auth#refresh"
      post "auth/password/forgot", to: "auth#forgot_password"
      post "auth/password/reset", to: "auth#reset_password"

      get    "sessions",     to: "auth#sessions"
      delete "sessions",     to: "auth#revoke_all_sessions"
      delete "sessions/:id", to: "auth#revoke_session"

      patch "password/change", to: "auth#change_password"

      get  "dashboard", to: "dashboard#show"

      resources :trading_accounts, only: %i[create update destroy] do
        member do
          post :regenerate_token
          put  :guards
        end
      end
      resources :copy_links, only: %i[create update destroy]

      post "positions/close_all",     to: "positions#close_all"
      post "positions/:ticket/close", to: "positions#close"
      post "orders",                  to: "orders#create"
      put  "copier",                  to: "copier#update"

      # extras (not used by the dashboard, handy for debugging)
      resources :mappings, only: :index do
        member { post :close }
      end
      get "audit/events",   to: "audit#events"
      get "audit/commands", to: "audit#commands"
    end
  end
end
