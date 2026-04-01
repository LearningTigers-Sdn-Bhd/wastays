Rails.application.routes.draw do
  get "help_center/index"
  get "help_center/show"
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "static_pages#home"

  # Help Center
  get "help", to: "help_center#index", as: :help_center
  get "help/:audience/:id", to: "help_center#show", as: :help_guide

  # API Namespace
  namespace :api do
    namespace :v1 do
      post "workflow_webhooks", to: "workflow_webhooks#create"
    end
  end

  # Public Booking Engine
  scope module: :public do
    resources :hotels, only: [ :index, :show ]
    resources :quotes, only: [ :create, :show ]
    resources :bookings, only: [ :show ]
    get "mock_payment", to: "payment_mocks#show", as: :mock_payment
    post "mock_payment", to: "payment_mocks#update"
    post "webhooks/:gateway", to: "webhooks#create", as: :payment_webhook
  end

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
    # ...
    resource :profile, only: [ :edit, :update ], controller: "profiles"
    get "audit_logs/index"
    get "margin_rules/index"
    get "margin_rules/create"
    get "margin_rules/destroy"
    get "dashboard", to: "dashboard#index"
    get "analytics", to: "dashboard#analytics"
    resources :hotels do
      member do
        post :approve
        post :suspend
      end
    end
    resources :bookings, only: [ :index, :show ] # Added stub
    resources :reconciliations, only: [ :index, :show ] do
      member do
        post :retry
        post :resolve
      end
    end
    get "reconciliations_dashboard", to: "reconciliations#index", as: :reconciliation_dashboard # Alias for layout
    resources :margin_rules, only: [ :index, :create, :destroy ]
    resources :audit_logs, only: [ :index ]
  end

  # Hotel admin dashboard
  namespace :hotel, module: :hotel_portal do
    resource :user_profile, only: [ :edit, :update ], controller: "user_profiles"
    get "dashboard", to: "dashboard#index"
    post "submit_for_review", to: "dashboard#submit_for_review"

    resource :profile, only: [ :edit, :update ]
    resource :property_policy, only: [ :edit, :update ]

    resources :room_types do
      resources :rates, only: [ :index, :create ]
      resources :inventories, only: [ :index, :create ]
    end

    resources :bookings, only: [ :index, :show, :update ] do
      member do
        post :check_in
        post :check_out
        post :cancel
      end
      resources :booking_notes, only: [ :create, :update, :destroy ], module: :bookings
    end

    resources :arrivals, only: [ :index ]
    resources :audit_logs, only: [ :index ]
    resources :reports, only: [ :index ]
    resources :inventory_dashboards, only: [ :index ], path: "inventory"
    get "inventory", to: "inventory_dashboards#index", as: :inventory_index
    resources :guests, only: [ :index ]
    resource :settings, only: [ :show, :update ], controller: "settings"
    resources :inventory_audit_logs, only: [ :index ]
  end
end
