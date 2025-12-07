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
        end
      end

      # Routes for user registration
      resources :users, only: [ :create ]

      # Routes for sessions (login/logout)
      post "/login", to: "sessions#create"
      post "/session/refresh", to: "sessions#refresh"
      get "/session/remaining", to: "sessions#remaining"
      delete "/logout", to: "sessions#destroy"
      get "/logged_in", to: "sessions#logged_in?"
      post "/password/forgot", to: "password_resets#create"
      post "/password/reset", to: "password_resets#update"
      # Maintenance mode
      get "/maintenance", to: "maintenance#show"
      namespace :admin do
        get "/maintenance", to: "maintenance#show"
        post "/maintenance", to: "maintenance#update"
      end

      namespace :admin do
        resources :bid_packs, path: "bid-packs", only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
        resources :users, only: [ :index, :update ] do
          member do
            post :grant_admin
            post :revoke_admin
            post :grant_superadmin
            post :revoke_superadmin
            post :ban
          end
        end
        resources :payments, only: [ :index ]
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

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
