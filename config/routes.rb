Rails.application.routes.draw do
  get "static_pages/home"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "static_pages#home"

  # Authentication
  scope module: :public do
    get "login", to: "sessions#new"
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy"

    get "register", to: "registrations#new"
    post "register", to: "registrations#create"
  end

  # Superadmin dashboard
  namespace :admin do
    get "dashboard", to: "dashboard#index"
  end

  # Hotel admin dashboard
  namespace :hotel do
    get "dashboard", to: "dashboard#index"
    resource :profile, only: [:edit, :update]
    resource :property_policy, only: [:edit, :update]
  end
end
