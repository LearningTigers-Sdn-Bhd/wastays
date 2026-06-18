require_relative "../app/constraints/superadmin_constraint"

Rails.application.routes.draw do
  mount RailsIcons::Engine, at: "/rails_icons"
  namespace :hotel_portal do
    get "room_blocks/create"
    get "room_blocks/destroy"
  end
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
        get :receipt
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
      match "*path", to: "preflight#handle", via: :options
      post "guest_sessions", to: "guest_sessions#create"
      post "workflow_webhooks", to: "workflow_webhooks#create"
      post "housekeeping_webhooks", to: "housekeeping_webhooks#create"
      post "complaint_webhooks", to: "complaint_webhooks#create"
      post "pre_checkin_links", to: "pre_checkin_links#create"
      resources :hotels, only: [ :index, :show ] do
        get "availability", on: :member
        namespace :ai_concierge do
          resources :inquiries, only: [ :create ]
        end
      end
      resources :quotes, only: [ :create, :show ]
      resources :bookings, only: [ :show ] do
        get "reminders", on: :member
        get "lookup", on: :collection
        resources :housekeeping_requests, only: [ :create ], module: :bookings
        resources :complaint_requests, only: [ :create ], module: :bookings
      end
    end
  end

  # Public Concierge (front-desk QR)
  scope "/concierge/:hotel_slug", module: "public/concierge", as: :concierge do
    get  "/",                      to: "home#show",            as: :home
    get  "check-in",               to: "check_ins#new",        as: :check_in
    post "check-in/lookup",        to: "check_ins#lookup",     as: :check_in_lookup
    get  "check-in/now",           to: "check_ins#check_in_now",     as: :check_in_now
    post "check-in/now",           to: "check_ins#submit_check_in",  as: :submit_check_in
    get  "check-in/success",       to: "check_ins#check_in_success", as: :check_in_success
    get  "check-out",              to: "check_outs#new",       as: :check_out
    post "check-out",              to: "check_outs#create",    as: :create_check_out
    get  "check-out/success",      to: "check_outs#success",   as: :check_out_success
    get  "book",                   to: "home#book",            as: :book
    get  "requests/new",           to: "requests#new",         as: :new_request
    post "requests",               to: "requests#create",      as: :requests
    get  "requests/success",       to: "requests#success",     as: :request_success
    get  "contact",                to: "contact#show",         as: :contact
  end

  # Public Booking Engine
  scope module: :public do
    resources :hotels, only: [ :index, :show ] do
      get :rate_calendar, on: :member
    end
    resources :quotes, only: [ :create, :show ] do
      member do
        get :guest_lookup
      end
    end
    resources :bookings, only: [ :show ] do
      member do
        get :receipt
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

    get "staff-invitations/:token", to: "staff_invitations#show", as: :staff_invitation
    patch "staff-invitations/:token", to: "staff_invitations#update"
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
        get :onboarding, to: "hotels/onboarding#index", as: :onboarding
      end
      member do
        get :onboarding, to: "hotels/onboarding#show"
        post :complete_onboarding, to: "hotels/onboarding#complete"
        post :save_onboarding_period, to: "hotels/onboarding#save_period"
        post :approve, to: "hotels/status#approve"
        post :suspend, to: "hotels/status#suspend"
        post :onboard_channex, to: "hotels/channel_managers#onboard_channex"
        post :full_refresh, to: "hotels/channel_managers#full_refresh"
        post :disconnect_channex, to: "hotels/channel_managers#disconnect_channex"
      end
      resources :onboarding_sessions, module: :hotels, only: [ :create, :show, :edit, :update, :destroy ] do
        member do
          post :complete
          post :cancel
        end
      end
    end
    resources :bookings, only: [ :index, :show ] do
      member do
        get :receipt
        get :invoice
      end
    end
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
    resources :exchange_rates, only: [ :index, :create, :update, :destroy ]
    resources :audit_logs, only: [ :index ]
    resources :api_keys, only: [ :index, :new, :create, :destroy ] do
      get :docs, on: :collection
    end
    resources :webhook_endpoints, only: [ :index, :create, :update, :destroy ] do
      member do
        post :test_ping
        patch :toggle
      end
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
      post :test_r2_connection, on: :collection
    end
    resources :plans, only: [ :index ] do
      collection do
        patch :update_matrix
      end
    end
  end

  # Hotel admin dashboard
  get "/hotel/settings", to: "hotel_portal/settings#index", as: :legacy_hotel_settings
  scope "/hotel/:hotel_id", module: :hotel_portal, as: :hotel do
    resource :user_profile, only: [ :edit, :update ], controller: "user_profiles"
    get "dashboard", to: "dashboard#index", as: :dashboard
    get "plan", to: "plans#show", as: :plan
    post "submit_for_review", to: "dashboard#submit_for_review", as: :submit_for_review

    resources :onboarding_sessions, only: [ :index ] do
      member do
        post :cancel
      end
    end

    resource :profile, only: [ :edit, :update ]
    resources :knowledge_policies do
      member { post :reindex }
    end
    resources :knowledge_faqs do
      member { post :reindex }
    end
    resources :knowledge_general_infos do
      member { post :reindex }
    end
    resources :knowledge_diagnostics, only: [ :index, :update ]
    delete "profile/photos/:photo_id", to: "profiles#destroy_photo", as: :profile_photo
    delete "profile/photos", to: "profiles#destroy_photos", as: :profile_photos
    patch "profile/photos/:photo_id/feature", to: "profiles#set_featured_photo", as: :profile_photo_feature
    post "profile/photo_queue", to: "profiles#enqueue_photo", as: :profile_photo_queue
    delete "profile/photo_queue", to: "profiles#clear_photo_queue", as: :clear_profile_photo_queue
    delete "profile/photo_queue/:signed_id", to: "profiles#remove_photo_from_queue", as: :profile_photo_queue_item
    post "profile/photo_queue/commit", to: "profiles#commit_photo_queue", as: :commit_profile_photo_queue
    resource :property_policy, only: [ :edit, :update ]
    resources :users, only: [ :index, :new, :create, :update, :destroy ], path: "staff" do
      patch :reactivate, on: :member
    end
    resources :staff_invitations, only: [ :update, :destroy ] do
      post :resend, on: :member
    end
    resources :roles, only: [ :index, :new, :create, :edit, :update, :destroy ], path: "roles-and-permissions" do
      patch :bulk_update, on: :collection
    end
    resources :general_ledger_maps, only: [ :index, :edit, :update ], path: "general-ledger-mappings"

    resources :room_types, except: [ :show ] do
      member do
        delete :destroy_photo
        delete :bulk_destroy_photos
      end
    end

    resources :nearby_attractions, except: [ :show ]
    resource :taxes_fees, only: [ :show, :update ], path: "taxes-fees"
    get "transaction-codes", to: "transaction_codes#show", as: :transaction_codes
    get "transaction-codes/new", to: "transaction_codes#new", as: :new_transaction_code
    post "transaction-codes", to: "transaction_codes#create"
    patch "transaction-codes/configuration", to: "transaction_codes#update_configuration", as: :transaction_code_configuration
    get "transaction-codes/:id/edit", to: "transaction_codes#edit", as: :edit_transaction_code
    patch "transaction-codes/:id", to: "transaction_codes#update", as: :transaction_code

    resources :bookings, only: [ :index, :show, :update ] do
      collection do
        post :sync, to: "bookings/syncs#create"
        get :availability, to: "bookings/availabilities#show"
        get :rate_options, to: "bookings/rate_options#show"
        get :stay_price, to: "bookings/prices#show"
        get :board, to: "bookings/board#index"
      end

      member do
        patch :move, to: "bookings/moves#update"
        post :check_in, to: "bookings/check_ins#create"
        post :check_out, to: "bookings/checkouts#create"
        post :reinstate, to: "bookings/reinstatements#create"
        post :mark_no_show, to: "bookings/no_shows#create"
        post :cancel, to: "bookings/cancellations#create"
        post :add_guest, to: "bookings/guests#create"
        post :process_late_checkout, to: "bookings/checkouts#process_late_checkout"
        delete "guests/:guest_id", to: "bookings/guests#destroy", as: :remove_guest
        post "housekeeping_requests/:housekeeping_request_id/complete", to: "bookings/housekeeping_requests#complete", as: :complete_housekeeping_request
        post "complaint_requests/:complaint_request_id/resolve", to: "bookings/complaint_requests#resolve", as: :resolve_complaint_request
      end

      resources :refund_requests, only: [ :new, :create ]
      resources :booking_notes, only: [ :create, :update, :destroy ], module: :bookings
    end
    scope "bookings/:booking_id/show/actions", as: :booking_show_action, module: "bookings/show/actions" do
      match "manage-guest", to: "manage_guests#show", via: [ :get, :post, :patch ], as: :manage_guest
      match "confirmation", to: "confirmation_actions#show", via: [ :get, :delete ], as: :confirmation
      match "manage-internal-notes", to: "manage_internal_notes#show", via: [ :get, :post, :patch ], as: :manage_internal_notes
    end
    scope "booking-transactions", as: :booking_transaction, module: "bookings/transactions" do
      match "new-booking", to: "new_bookings#show", via: [ :get, :post ], as: :new_booking
      match "walk-in-check-in", to: "walk_in_check_ins#show", via: [ :get, :post ], as: :walk_in_check_in
      match "backdated-check-in", to: "backdated_check_ins#show", via: [ :get, :post ], as: :backdated_check_in
      match "backdated-check-in/:booking_id", to: "backdated_check_ins#show", via: [ :get, :post ], as: :booking_backdated_check_in
      match "edit-booking/:booking_id", to: "edit_bookings#show", via: [ :get, :patch ], as: :edit_booking
      match "edit-booking-timeline/:booking_id", to: "edit_booking_timelines#show", via: [ :get, :patch ], as: :edit_booking_timeline
      match "amend-stay/:booking_id", to: "amend_stays#show", via: [ :get, :patch ], as: :amend_stay
      get "check-in-reservation/:booking_id", to: "check_in_reservations#show", as: :check_in_reservation
      get "check-out/:booking_id", to: "check_outs#show", as: :check_out
      get "late-checkout/:booking_id", to: "late_checkouts#show", as: :late_checkout
      get "reinstate-no-show/:booking_id", to: "reinstate_no_shows#show", as: :reinstate_no_show
      get "mark-no-show/:booking_id", to: "mark_no_shows#show", as: :mark_no_show
      get "cancel-booking/:booking_id", to: "cancel_bookings#show", as: :cancel_booking
    end

    resources :folios, only: [ :index, :show ], param: :booking_id do
      get :invoice, on: :member
      resources :transactions, only: [ :create ], controller: "folios/transactions" do
        post :reverse, on: :member
      end
    end

    get "requests", to: "requests#index", as: :requests
    get "requests/archive", to: "requests#archive", as: :request_archive
    patch "requests/:kind/:request_id", to: "requests#update_status", as: :request_status
    post "requests/:kind/:request_id/cancel", to: "requests#cancel_request", as: :cancel_request
    patch "requests/:kind/:request_id/archive", to: "requests#archive_request", as: :archive_request
    patch "requests/:kind/:request_id/unarchive", to: "requests#unarchive_request", as: :unarchive_request

    patch "checkout-requests/:id/complete", to: "checkout_requests#complete", as: :complete_checkout_request

    resources :room_locks, only: [ :create ] do
      collection do
        delete :release
      end
    end

    resources :arrivals, only: [ :index ]
    resources :checked_out_guests, only: [ :index ]
    resources :audit_logs, only: [ :index ]
    resources :notification_logs, only: [ :index ] do
      post :resend, on: :member
    end
    resources :reports, only: [ :index ] do
      collection do
        get :payouts
        get :breakdown, defaults: { format: "html" }
        get :arrivals_departures
        get :daily_occupancy
        get :daily_revenue
        get :managers_flash
        get :outstanding_balance
        get :deposit_liability
        get :folio_ledger
        get :journal_batches
        get :sst      end
    end
    resources :night_audits, only: [ :index, :show, :create ] do
      member do
        get :resolve
        get :blockers
      end
    end
    resources :inventory_dashboards, only: [ :index ], path: "inventory" do
      collection do
        post :apply_pricing_rules
        post :apply_availability_override
        post :bulk_save_ari
        post :batch_save_ari
        delete "pricing_tiers/:rule_type", action: :destroy_pricing_tier_rule, as: :destroy_pricing_tier_rule
        delete "public_holidays/:id", action: :destroy_public_holiday_rule, as: :destroy_public_holiday_rule
      end
    end
    get "inventory", to: "inventory_dashboards#index", as: :inventory_index
    resources :guests, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
      get :search, on: :collection
    end
    resources :in_house_guests, only: [ :index ]
    get "settings", to: "settings#index", as: :settings
    get "settings/edit", to: "settings#edit", as: :edit_settings
    patch "settings", to: "settings#update"
    resource :concierge_qr, only: [ :show ], controller: "concierge_qr"
    resources :hotel_taxes, only: %i[index new create edit update destroy]
    resources :inventory_audit_logs, only: [ :index ]
    resources :global_search, only: [ :index ]
    get "room-status", to: "room_status_board#index", as: :room_status_board
    resources :room_statuses, only: [ :update ]
    resources :room_blocks, only: [ :create, :update, :destroy ] do
      post :finish, on: :member
    end
  end
end
