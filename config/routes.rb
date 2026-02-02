Rails.application.routes.draw do
  root "api/v1/auctions#index"

  namespace :api do
    namespace :v1 do
      resources :checkouts, only: [ :create ]
      get "/checkout/status", to: "checkouts#status"
      get "/checkout/success", to: "checkouts#success"

      resources :bid_packs, only: [ :index ]
      # post '/bid_packs/:id/purchase', to: 'bid_packs#purchase'

      resources :auctions do
        resources :bids, only: [ :create ]
        resources :bid_history, only: [ :index ]

        member do
          post :extend_time
          post :watch, to: "auction_watches#create"
          delete :watch, to: "auction_watches#destroy"
        end
      end

      # Routes for user registration
      resources :users, only: [ :create ]
      post "/signup", to: "registrations#create"

      # Account management
      resource :account, only: [ :show, :update ], controller: :account
      post "/account/password", to: "account_passwords#create"
      get "/account/security", to: "account_security#show"
      post "/account/email-change", to: "account_emails#change"
      delete "/account", to: "account_deletions#destroy"
      post "/account/2fa/setup", to: "account_two_factor#setup"
      post "/account/2fa/verify", to: "account_two_factor#verify"
      post "/account/2fa/disable", to: "account_two_factor#disable"

      get "/account/notifications", to: "account_notifications#show"
      put "/account/notifications", to: "account_notifications#update"

      get "/account/sessions", to: "account_sessions#index"
      delete "/account/sessions", to: "account_sessions#revoke_others"
      delete "/account/sessions/:id", to: "account_sessions#destroy"
      post "/account/sessions/revoke_others", to: "account_sessions#revoke_others"

      get "/account/data/export", to: "account_exports#show"
      post "/account/data/export", to: "account_exports#create"
      get "/account/export", to: "account_exports#show"
      post "/account/export", to: "account_exports#create"
      get "/account/export/download", to: "account_exports#download"

      post "/email_verifications/resend", to: "email_verifications#resend"
      get "/email_verifications/verify", to: "email_verifications#verify"

      # Routes for sessions (login/logout)
      post "/login", to: "sessions#create"
      post "/session/refresh", to: "sessions#refresh"
      get "/session/remaining", to: "sessions#remaining"
      delete "/logout", to: "sessions#destroy"
      get "/logged_in", to: "sessions#logged_in?"
      get "/diagnostics/auth", to: "diagnostics#auth"
      get "/auth/debug", to: "auth_debug#show"
      get "/csrf", to: "csrf#show"
      get "/health", to: "health#show"
      post "/password/forgot", to: "password_resets#create"
      post "/password/reset", to: "password_resets#update"
      post "/age_gate/accept", to: "age_gate#accept"
      post "/stripe/webhooks", to: "stripe_webhooks#create"
      # Maintenance mode
      get "/maintenance", to: "maintenance#show"

      # Wallet (credits)
      get "/wallet", to: "wallet#show"
      get "/wallet/transactions", to: "wallet#transactions"

      get "/me", to: "me#show"
      get "/me/purchases", to: "me/purchases#index"
      get "/me/purchases/:id", to: "me/purchases#show"
      get "/me/activity", to: "me/activity#index"
      get "/me/wins", to: "me/wins#index"
      get "/me/wins/:auction_id", to: "me/wins#show"
      post "/me/wins/:auction_id/claim", to: "me/wins#claim"
      get "/me/notifications", to: "me/notifications#index"
      match "/me/account", to: "legacy#not_found", via: :all
      match "/me/account/*path", to: "legacy#not_found", via: :all

      post "/uploads", to: "uploads#create"

      namespace :admin do
        get "/maintenance", to: "maintenance#show"
        post "/maintenance", to: "maintenance#update"
      end

      namespace :admin do
        resources :bid_packs, path: "bid-packs", only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
        resources :auctions, only: [ :index, :show ]
        post "/fulfillments/:id/process", to: "fulfillments#process_fulfillment"
        post "/fulfillments/:id/ship", to: "fulfillments#ship"
        post "/fulfillments/:id/complete", to: "fulfillments#complete"
        resources :users, only: [ :index, :update ] do
          member do
            post :grant_admin
            post :revoke_admin
            post :grant_superadmin
            post :revoke_superadmin
            post :ban
          end
        end
        resources :payments, only: [ :index, :show ] do
          member do
            post :refund
            post :repair_credits
          end
        end
        post "/audit", to: "audit#create"
      end
    end
  end

  # Interactive docs + raw OpenAPI spec
  mount OasRails::Engine => "/api-docs"
  get "/docs", to: redirect("/api-docs")
  get "/docs.json", to: redirect("/api-docs.json")

  # Quiet missing favicon to avoid log noise
  get "/favicon.ico", to: proc { [ 204, { "Content-Type" => "image/x-icon" }, [] ] }

  get "/cable/health", to: "cable_health#show"
  mount ActionCable.server => "/cable"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
