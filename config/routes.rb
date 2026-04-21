require_relative "../app/constraints/superadmin_constraint"

Rails.application.routes.draw do
  if Rails.env.development?
    require "letter_opener_web"
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end
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

  # Guest Portal
  scope "/guest", module: :guest, as: :guest do
    get    "login",               to: "sessions#new",              as: :login
    post   "login",               to: "sessions#create"
    get    "verify",              to: "sessions#verify",           as: :verify
    post   "request_magic_link",  to: "sessions#request_magic_link", as: :request_magic_link
    delete "logout",              to: "sessions#destroy",          as: :logout
    get    "dashboard",           to: "dashboard#index",           as: :dashboard
    resources :bookings, only: [ :index, :show ] do
      member do
        get :invoice
      end
      resources :refund_requests, only: [ :new, :create ]
    end
    resources :refund_requests, only: [ :index, :show ]
    resources :global_search, only: [ :index ]
  end

  # API Namespace
  namespace :api do
    namespace :v1 do
      post "guest_sessions", to: "guest_sessions#create"
      post "workflow_webhooks", to: "workflow_webhooks#create"
      post "housekeeping_webhooks", to: "housekeeping_webhooks#create"
      post "complaint_webhooks", to: "complaint_webhooks#create"
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
    resources :quotes, only: [ :create, :show ] do
      member do
        get :guest_lookup
      end
    end
    resources :bookings, only: [ :show ] do
      member do
        get :invoice
        get :voucher
      end
    end
    resources :pre_checkins, only: [ :show, :update ], param: :token, path: "pre-checkin" do
      post :cancel, on: :member
    end
    post "payments/checkout_session", to: "payments#checkout_session", as: :checkout_payment_session
    get "payments/verify", to: "payments#verify"
    post "payments/verify", to: "payments#verify", as: :verify_payment
    get "mock_payment", to: "payment_mocks#show", as: :mock_payment
    post "mock_payment", to: "payment_mocks#update"
    post "webhooks/channex", to: "channel_manager_webhooks#channex", as: :channex_webhook
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
    resource :profile, only: [ :edit, :update ], controller: "profiles"
    get "audit_logs/index"
    get "margin_rules/index"
    get "margin_rules/create"
    get "margin_rules/destroy"
    get "dashboard", to: "dashboard#index"
    get "analytics", to: "dashboard#analytics"
    resources :hotels do
      collection do
        get :onboarding, action: :onboarding_index
      end
      member do
        get :onboarding
        post :create_onboarding_session
        post :complete_onboarding_session
        post :complete_onboarding
        post :approve
        post :suspend
        post :onboard_channex
        post :disconnect_channex
      end
    end
    resources :bookings, only: [ :index, :show ] # Added stub
    resources :salespersons, only: [ :index, :create, :update, :destroy ]
    resources :reconciliations, only: [ :index, :show ] do
      member do
        post :retry
        post :resolve
      end
    end
    get "reconciliations_dashboard", to: "reconciliations#index", as: :reconciliation_dashboard # Alias for layout
    resources :payout_batches, only: [ :index, :show, :update ] do
      collection do
        get :export_payouts_csv
      end
      member do
        post :mark_as_paid
      end
    end
    resources :payouts, only: [ :index ] do
      collection do
        get :export_payouts_csv
        post :mark_as_paid
      end
    end
    resources :global_search, only: [ :index ]
    resources :margin_rules, only: [ :index, :create, :destroy ]
    resources :setup_fee_rules, only: [ :index, :create, :destroy ]
    resources :audit_logs, only: [ :index ]
    resources :api_keys, only: [ :index, :new, :create, :destroy ] do
      get :docs, on: :collection
    end
    resources :observation_deck, only: [ :index, :show ], constraints: SuperadminConstraint.new do
      collection do
        delete :clear
        post :acknowledge
        post :update_config
      end
      member do
        post :analyze
      end
    end
    resource :refund_policy, only: [ :show, :update, :destroy ]
    resources :refund_requests, only: [ :index, :show ] do
      member do
        patch :approve
        patch :reject
        patch :complete
      end
    end
    resource :integrations, only: [ :show, :update, :destroy ] do
      post :test_ping, on: :collection
    end
  end

  # Hotel admin dashboard
  get "/hotel/settings", to: "hotel_portal/settings#index", as: :legacy_hotel_settings
  scope "/hotel/:hotel_id", module: :hotel_portal, as: :hotel do
    resource :user_profile, only: [ :edit, :update ], controller: "user_profiles"
    get "dashboard", to: "dashboard#index", as: :dashboard
    get "onboarding-sessions", to: "dashboard#onboarding_sessions", as: :onboarding_sessions
    post "onboarding-sessions/:session_id/cancel", to: "dashboard#cancel_onboarding_session", as: :cancel_onboarding_session
    post "submit_for_review", to: "dashboard#submit_for_review", as: :submit_for_review

    resource :profile, only: [ :edit, :update ]
    delete "profile/photos/:photo_id", to: "profiles#destroy_photo", as: :profile_photo
    delete "profile/photos", to: "profiles#destroy_photos", as: :profile_photos
    patch "profile/photos/:photo_id/feature", to: "profiles#set_featured_photo", as: :profile_photo_feature
    post "profile/photo_queue", to: "profiles#enqueue_photo", as: :profile_photo_queue
    delete "profile/photo_queue", to: "profiles#clear_photo_queue", as: :clear_profile_photo_queue
    delete "profile/photo_queue/:signed_id", to: "profiles#remove_photo_from_queue", as: :profile_photo_queue_item
    post "profile/photo_queue/commit", to: "profiles#commit_photo_queue", as: :commit_profile_photo_queue
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
        post "housekeeping_requests/:housekeeping_request_id/complete", to: "bookings#complete_housekeeping_request", as: :complete_housekeeping_request
        patch "complaint_requests/:complaint_request_id", to: "bookings#update_complaint_request", as: :update_complaint_request
        post "complaint_requests/:complaint_request_id/resolve", to: "bookings#resolve_complaint_request", as: :resolve_complaint_request
      end
      resources :booking_notes, only: [ :create, :update, :destroy ], module: :bookings
    end

    get "requests", to: "requests#index", as: :requests
    get "requests/archive", to: "requests#archive", as: :request_archive
    patch "requests/:kind/:request_id", to: "requests#update_status", as: :request_status
    post "requests/:kind/:request_id/cancel", to: "requests#cancel_request", as: :cancel_request
    patch "requests/:kind/:request_id/archive", to: "requests#archive_request", as: :archive_request
    patch "requests/:kind/:request_id/unarchive", to: "requests#unarchive_request", as: :unarchive_request

    resources :arrivals, only: [ :index ]
    resources :audit_logs, only: [ :index ]
    resources :reports, only: [ :index ] do
      collection do
        get :payouts
        get :breakdown, defaults: { format: "html" }
      end
    end
    resources :inventory_dashboards, only: [ :index ], path: "inventory" do
      collection do
        post :apply_pricing_rules
        post :apply_availability_override
        delete "pricing_tiers/:rule_type", action: :destroy_pricing_tier_rule, as: :destroy_pricing_tier_rule
        delete "public_holidays/:id", action: :destroy_public_holiday_rule, as: :destroy_public_holiday_rule
      end
    end
    get "inventory", to: "inventory_dashboards#index", as: :inventory_index
    resources :guests, only: [ :index, :show ]
    resources :in_house_guests, only: [ :index ]
    get "settings", to: "settings#index", as: :settings
    get "settings/edit", to: "settings#edit", as: :edit_settings
    patch "settings", to: "settings#update"
    resources :inventory_audit_logs, only: [ :index ]
    resources :global_search, only: [ :index ]
  end
end
