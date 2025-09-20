Rails.application.routes.draw do
  root "api/v1/auctions#index"
  
  namespace :api do
    namespace :v1 do
      resources :auctions
    end  
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
