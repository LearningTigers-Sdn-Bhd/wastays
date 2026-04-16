Rails.application.routes.draw do
  get "help_center/index"
  get "help_center/show"
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "static_pages#home"
  get "for-hotels", to: "static_pages#for_hotels", as: :for_hotels
  get "explore", to: "static_pages#explore", as: :explore
  get "privacy-policy", to: "legal_pages#privacy_policy", as: :privacy_policy
  get "terms-and-conditions", to: "legal_pages#terms_and_conditions", as: :terms_and_conditions

  # Help Center
  get "help", to: "help_center#index", as: :help_center
  get "help/:audience/:id", to: "help_center#show", as: :help_guide

  # API Namespace
  namespace :api do
    namespace :v1 do
      post "workflow_webhooks", to: "workflow_webhooks#create"
      post "pre_checkin_links", to: "pre_checkin_links#create"
      resources :hotels, only: [ :index, :show ] do
        get "availability", on: :member
      end
      resources :quotes, only: [ :create, :show ]
      resources :bookings, only: [ :show ] do
        get "reminders", on: :member
      end
    end
  end

  # Public Booking Engine
  scope module: :public do
    resources :hotels, only: [ :index, :show ]
    resources :quotes, only: [ :create, :show ]
    resources :bookings, only: [ :show ]
    resources :pre_checkins, only: [ :show, :update ], param: :token, path: "pre-checkin" do
      post :cancel, on: :member
    end
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
    resources :api_keys, only: [ :index, :new, :create, :destroy ] do
      get :docs, on: :collection
    end
    end

  # Hotel admin dashboard
  get "/hotel/settings", to: "hotel_portal/settings#index", as: :legacy_hotel_settings
  scope "/hotel/:hotel_id", module: :hotel_portal, as: :hotel do
    resource :user_profile, only: [ :edit, :update ], controller: "user_profiles"
    get "dashboard", to: "dashboard#index", as: :dashboard
    post "submit_for_review", to: "dashboard#submit_for_review", as: :submit_for_review

    resource :profile, only: [ :edit, :update ]
    delete "profile/photos/:photo_id", to: "profiles#destroy_photo", as: :profile_photo
    delete "profile/photos", to: "profiles#destroy_photos", as: :profile_photos
    patch "profile/photos/:photo_id/feature", to: "profiles#set_featured_photo", as: :profile_photo_feature
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
    resources :inventory_dashboards, only: [ :index, :create ], path: "inventory"
    get "inventory", to: "inventory_dashboards#index", as: :inventory_index
    resources :guests, only: [ :index, :show ]
    resources :in_house_guests, only: [ :index ]
    get "settings", to: "settings#index", as: :settings
    get "settings/edit", to: "settings#edit", as: :edit_settings
    patch "settings", to: "settings#update"
    resources :inventory_audit_logs, only: [ :index ]
  end
end
