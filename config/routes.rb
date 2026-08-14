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

  # Fast, UI-less sign-in for system/request specs only. Sets the session the
  # same way SessionsController#create does, without the login round-trip.
  if Rails.env.test?
    get "test/sign_in/:user_id", to: "test_sessions#create", as: :test_sign_in
  end

  # PanelsUI component library showcase (not exposed in production).
  unless Rails.env.production?
    get "system-design", to: "system_designs#index", as: :system_design
    post "system-design/submit-form", to: "system_designs#submit_form", as: :system_design_submit_form
    post "system-design/confirm-alert-dialog", to: "system_designs#confirm_alert_dialog", as: :system_design_confirm_alert_dialog
  end

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
        patch :toggle_dnd
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
    namespace :v2 do
      resources :bookings, only: [ :show ]
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
        get :confirmation
        get :receipt
        get :invoice
        get :voucher
      end
    end
    resources :receipts, only: [ :show ]
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
    get "corporate-invitations/:token", to: "corporate_invitations#show", as: :corporate_invitation
    patch "corporate-invitations/:token", to: "corporate_invitations#update"
  end

  scope "/corporate", module: :corporate_portal, as: :corporate do
    get "dashboard", to: "dashboard#index", as: :dashboard
    resource :profile, only: [ :show ]
    resources :ar_invoices, only: [ :index, :show ], path: "invoices"
    resources :ar_statements, only: [ :index, :show ], path: "statements"
    resources :ar_payments, only: [ :index, :show ], path: "payments" do
      collection do
        get :pay_invoices, path: "pay-invoices"
        get :pay_balance, path: "pay-balance"
        get :choose_method, path: "choose-method"
        post :review
        post :checkout_session
        get :verify
        post :verify
      end
    end
    resources :ar_payment_submissions, only: [ :show, :new, :create ], path: "payment-submissions"
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
      member do
        get :onboarding, to: "hotels/onboarding#show"
        get "onboarding/:tab", to: "hotels/onboarding#show", as: :onboarding_tab,
                               constraints: { tab: /history|training/ }
        post "onboarding/request_changes", to: "hotels/onboarding#request_changes", as: :request_onboarding_changes
        post "onboarding/approve", to: "hotels/onboarding#approve", as: :approve_onboarding
        post :save_onboarding_period, to: "hotels/onboarding#save_period"
        post "onboarding/setup_lock", to: "hotels/onboarding#toggle_setup_lock", as: :toggle_setup_lock
        post :approve, to: "hotels/status#approve"
        post :suspend, to: "hotels/status#suspend"
        post :onboard_channex, to: "hotels/channel_managers#onboard_channex"
        post :full_refresh, to: "hotels/channel_managers#full_refresh"
        post :disconnect_channex, to: "hotels/channel_managers#disconnect_channex"
        post :repair_channex_mapping, to: "hotels/channel_managers#repair_mapping"
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
    resources :booking_sources, only: [ :index, :new, :create, :edit, :update ] do
      member do
        patch :toggle
      end
      collection do
        patch :reorder
        get :icon_preview
      end
    end
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
  get "/hotel/:hotel_id/settings/property/hotel-details", to: "hotel_portal/profiles#edit", as: :edit_hotel_profile
  scope "/hotel/:hotel_id", module: :hotel_portal, as: :hotel do
    resource :training_decision, only: [] do
      post :keep
      post :reset
    end

    resource :user_profile, only: [ :edit, :update ], controller: "user_profiles"
    get "onboarding", to: "onboarding#index", as: :onboarding
    get "onboarding/:section_key", to: "onboarding#show", as: :onboarding_section
    patch "onboarding/:section_key", to: "onboarding#update"
    resource :onboarding_submission, only: :create
    resource :setup_lock, only: :show
    get "dashboard", to: "dashboard#index", as: :dashboard

    resources :onboarding_sessions, only: [ :index ] do
      member do
        post :cancel
      end
    end

    resource :property_policy, only: [ :edit, :update ]
    scope "accounts-receivable" do
      resources :corporate_accounts, only: [ :index, :new, :create, :edit, :update ], path: "corporate-accounts" do
        member do
          patch :suspend
          patch :reactivate
        end
      end
      get "aging", to: "ar_invoices#aging", as: :ar_aging
      get "agent-summary", to: "ar_invoices#agent_summary", as: :ar_agent_summary
      resources :ar_invoices, only: [ :index, :show ], path: "invoices" do
        get :pdf, on: :member
      end
      resources :ar_statements, only: [ :index, :show ], path: "statements"
      resources :ar_payments, only: [ :index, :show, :new, :create ], path: "payments" do
        get :eligible_invoices, on: :collection
        resources :allocations, only: [ :create ], controller: "ar_payment_allocations" do
          resource :reversal, only: [ :create ], controller: "ar_payment_allocation_reversals"
        end
      end
      resources :ar_payment_submissions, only: [ :show ], path: "payment-submissions" do
        member do
          patch :reject
        end
      end
    end

    resources :corporate_invitations, only: [ :destroy ], path: "corporate-invitations" do
      post :resend, on: :member
    end
    get "room_groups", to: redirect("/hotel/%{hotel_id}/settings/property/room-groups"), as: :legacy_room_groups
    get "stay-view", to: "stay_view/board#index", as: :stay_view
    scope "stay-view", module: :stay_view, as: :stay_view do
      get "rooms/:room_type_id/:room_number/status", to: "room_operations#edit", as: :room_status
      patch "rooms/:room_type_id/:room_number/status", to: "room_operations#update"
      resources :room_blocks, only: [ :new, :edit, :create, :update, :destroy ] do
        post :finish, on: :member
      end
      resources :housekeeping_requests, only: [] do
        resource :assignment, only: [ :edit, :update ], controller: "housekeeping_assignments"
        resource :status, only: [ :edit, :update ], controller: "housekeeping_statuses"
      end
    end
    resources :bookings, only: [ :index, :show, :update ] do
      collection do
        post :sync, to: "bookings/syncs#create"
        get :availability, to: "bookings/availabilities#show"
        get :rate_options, to: "bookings/rate_options#show"
        get :stay_price, to: "bookings/prices#show"
        get :payment_quote, to: "bookings/prices#payment_quote"
        get :room_row, to: "bookings/room_rows#show"
      end

      member do
        patch :move, to: "bookings/moves#update"
        post "housekeeping_requests/:housekeeping_request_id/complete", to: "bookings/housekeeping_requests#complete", as: :complete_housekeeping_request
        post "complaint_requests/:complaint_request_id/resolve", to: "bookings/complaint_requests#resolve", as: :resolve_complaint_request
      end

      resources :refund_requests, only: [ :new, :create ]
      resource :guest_registration_card, only: [ :show, :update, :destroy ], module: :bookings
      resource :guest_registration_card_pdf, only: [ :show ], module: :bookings
      resources :guest_registration_note_templates, only: [ :index, :new, :create, :edit, :update, :destroy ], module: :bookings
      resource :reservation_voucher, only: [ :show ], module: :bookings
      resource :tourism_tax_voucher, only: [ :show ], module: :bookings do
        post :issue
      end

      resource :workspace, only: [ :show, :update ], module: :bookings do
        get :audit_trail
        patch :update_room_rate, controller: :workspace_actions
        post :add_billing_party, controller: :workspace_actions
        patch :update_billing_terms, controller: :workspace_actions
        patch :archive_billing_party, controller: :workspace_actions
        post :allocate_deposit, controller: :workspace_actions
        post :record_deposit, controller: :workspace_actions
        post :return_deposit, controller: :workspace_actions
        post :refund_deposit, controller: :workspace_actions
        post :reverse_deposit_application, controller: :workspace_actions
        post :reverse_deposit_allocation, controller: :workspace_actions
        post :collect_security_deposit, controller: :workspace_actions
        post :release_security_deposits, controller: :workspace_actions
        post :complete_housekeeping_request, controller: :workspace_actions
        post :resolve_complaint_request, controller: :workspace_actions
      end
    end
    get "bookings/:booking_id/group-statement", to: "bookings/group_statements#show", as: :booking_group_statement
    scope "booking-actions", as: :booking_action, module: "bookings/actions" do
      get "audit-trail/:booking_id", to: "audit_trails#show", as: :audit_trail
      get "show-booking/:booking_id", to: "summaries#show", as: :show_booking
      get "show-booking/:booking_id/print-send", to: "documents#show", as: :group_print_send
      post "show-booking/:booking_id/print-send/resend", to: "documents#resend", as: :group_print_send_resend
      match "new-booking", to: "new_bookings#show", via: [ :get, :post ], as: :new_booking
      match "quick-booking", to: "quick_bookings#show", via: [ :get, :post ], as: :quick_booking
      match "walk-in-check-in", to: "walk_in_check_ins#show", via: [ :get, :post ], as: :walk_in_check_in
      match "backdated-check-in", to: "backdated_check_ins#show", via: [ :get, :post ], as: :backdated_check_in
      match "edit-dates/:booking_id", to: "booking_dates#show", via: [ :get, :patch ], as: :edit_dates
      match "edit-room/:booking_id", to: "room_assignments#show", via: [ :get, :patch ], as: :edit_room
      match "edit-rate/:booking_id", to: "rate_changes#show", via: [ :get, :patch ], as: :edit_rate
      match "check-in/:booking_id", to: "check_ins#show", via: [ :get, :post ], as: :check_in
      match "cancel-booking/:booking_id", to: "cancellations#show", via: [ :get, :post ], as: :cancel_booking
      match "void-booking/:booking_id", to: "voids#show", via: [ :get, :post ], as: :void_booking
      match "mark-no-show/:booking_id", to: "no_shows#show", via: [ :get, :post ], as: :mark_no_show
      match "undo-check-in/:booking_id", to: "undo_check_ins#show", via: [ :get, :post ], as: :undo_check_in
      match "review-backdated-check-in/:booking_id", to: "review_backdated_check_ins#show", via: [ :get, :post ], as: :review_backdated_check_in
      match "repair-no-show-folio/:booking_id", to: "no_show_folio_repairs#show", via: [ :get, :post ], as: :repair_no_show_folio
      match "reinstate-no-show/:booking_id", to: "reinstatements#show", via: [ :get, :post ], as: :reinstate_no_show
      match "late-checkout/:booking_id", to: "late_checkouts#show", via: [ :get, :post ], as: :late_checkout
      get "checkout/:booking_id/folio-status", to: "checkouts#folio_status", as: :checkout_folio_status
      match "checkout/:booking_id/deposits/:deposit_id", to: "deposit_settlements#show", via: [ :get, :post ], as: :checkout_deposit_settlement
      match "checkout/:booking_id", to: "checkouts#show", via: [ :get, :post ], as: :checkout
      match "manage-guest/:booking_id", to: "guests#show", via: [ :get, :post, :patch ], as: :manage_guest
      match "manage-billing-party/:booking_id", to: "billing_parties#show", via: [ :get, :post, :patch, :delete ], as: :manage_billing_party
      match "remove-guest/:booking_id/:booking_guest_id", to: "guests#remove", via: [ :get, :delete ], as: :remove_guest
      patch "set-primary-guest/:booking_id/:booking_guest_id", to: "guests#set_primary", as: :set_primary_guest
      match "internal-notes/:booking_id", to: "internal_notes#show", via: [ :get, :post, :patch ], as: :internal_notes
      match "internal-notes/:booking_id/:note_id/delete", to: "internal_notes#delete", via: [ :get, :delete ], as: :delete_internal_note
    end

    scope "request-actions", as: :request_action, module: "requests/actions" do
      # A request is one of three tables, so it travels as its kind and its id
      # the way it does everywhere else on the board.
      get "show-request/:kind/:request_id", to: "details#show", as: :show_request
    end

    scope "folio-actions", as: :folio_action, module: "folios/actions" do
      match "post-transaction/:booking_id", to: "transactions#show", via: [ :get, :post ], as: :post_transaction
      get "extra-charge-quote/:booking_id", to: "transactions#quote", as: :extra_charge_quote
      get "discount-quote/:booking_id", to: "transactions#discount_quote", as: :discount_quote
      match "move-transaction/:booking_id/:transaction_id", to: "transaction_moves#show", via: [ :get, :post ], as: :move_transaction
      match "split-transaction/:booking_id/:transaction_id", to: "transaction_splits#show", via: [ :get, :post ], as: :split_transaction
      match "reverse-transaction/:booking_id/:transaction_id", to: "transaction_reversals#show", via: [ :get, :post ], as: :reverse_transaction
      match "new-window/:booking_id", to: "windows#show", via: [ :get, :post ], as: :new_window
      match "edit-window/:booking_id/:folio_id", to: "windows#show", via: [ :get, :patch ], as: :edit_window
      match "close-window/:booking_id/:folio_id", to: "window_closures#show", via: [ :get, :post ], as: :close_window
      match "reopen-window/:booking_id/:folio_id", to: "window_reopenings#show", via: [ :get, :post ], as: :reopen_window
      match "billing-routes/:booking_id", to: "billing_routes#show", via: [ :get, :post ], as: :billing_routes
      match "group-billing-routes/:booking_id", to: "group_billing_routes#show", via: [ :get, :post ], as: :group_billing_routes
    end

    resources :folios, only: [ :index, :show ], param: :booking_id do
      collection do
        get "needs-attention", to: "folios#needs_attention", as: :needs_attention
      end
    end
    get "folio-documents/:folio_id/invoice", to: "folios#invoice", as: :folio_invoice
    get "folio-documents/:folio_id/invoice/revisions/:revision_number", to: "folios#invoice", as: :folio_invoice_revision
    get "folio-documents/:folio_id/ledger", to: "folios#ledger", as: :folio_ledger

    get "requests", to: "requests#index", as: :requests
    # The rest of one column, read from a cursor rather than a page number.
    get "requests/columns/:column", to: "requests#column", as: :requests_column
    # Putting a request in a lane -- dragged there, or asked for by the button on
    # the card. One endpoint, so the two gestures cannot mean different things.
    patch "requests/move", to: "requests#move", as: :requests_move
    resources :housekeeping_tasks, only: [ :index ]
    patch "housekeeping-tasks/rooms/:room_type_id/:room_number/status",
          to: "housekeeping_tasks#update_room_status", as: :housekeeping_room_status
    patch "housekeeping-tasks/rooms/:room_type_id/:room_number/assignment",
          to: "housekeeping_tasks#update_room_assignment", as: :housekeeping_room_assignment
    get "housekeeping-tasks/rooms/:room_type_id/:room_number/remarks/edit",
        to: "housekeeping_tasks#edit_remarks", as: :edit_housekeeping_room_remarks
    patch "housekeeping-tasks/rooms/:room_type_id/:room_number/remarks",
          to: "housekeeping_tasks#update_remarks", as: :housekeeping_room_remarks
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

    get "front-desk", to: "front_desk#index", as: :front_desk
    resources :arrivals, only: [ :index ]
    resources :checked_out_guests, only: [ :index ]
    resources :audit_logs, only: [ :index ]
    resources :notification_logs, only: [ :index ] do
      post :resend, on: :member
    end
    resources :channel_settlement_receipts, only: %i[new create], path: "ota-settlement-receipts"
    resources :reports, only: [ :index ] do
      collection do
        get :payouts
        get :breakdown, defaults: { format: "html" }
        get :guest_reports
        get :arrivals_departures, to: redirect { |params, request| "/hotel/#{params[:hotel_id]}/reports/guest_reports#{request.query_string.present? ? "?#{request.query_string}" : ""}" }
        get :daily_occupancy
        get :daily_report
        get "daily_revenue/cell", to: "reports#daily_revenue_cell", as: :daily_revenue_cell
        get "daily_revenue/source", to: "reports#daily_revenue_source_bookings", as: :daily_revenue_source_bookings
        get :daily_revenue, to: redirect { |params, request|
          destination = "/hotel/#{params[:hotel_id]}/reports/daily_report"
          request.query_string.present? ? "#{destination}?#{request.query_string}" : destination
        }
        get :managers_flash, to: redirect { |params, request|
          destination = "/hotel/#{params[:hotel_id]}/reports/daily_occupancy"
          request.query_string.present? ? "#{destination}?#{request.query_string}" : destination
        }
        get :outstanding_balance
        get :channel_settlements
        get :deposit_liability
        get :folio_ledger
        get :journal_batches
        get :refund_report
        get :extra_charge
        get :tax_compliance
        get :tourism_tax, to: redirect { |params, request|
          format = params[:format].to_s
          extension = format.present? ? ".#{format}" : ""
          qs = request.query_string.split("&").reject { |pair| pair.start_with?("tab=") }.join("&")
          "/hotel/#{params[:hotel_id]}/reports/tax_compliance#{extension}?tab=tourism_tax#{qs.present? ? "&#{qs}" : ""}"
        }
        get :sst, to: redirect { |params, request|
          format = params[:format].to_s
          extension = format.present? ? ".#{format}" : ""
          qs = request.query_string.split("&").reject { |pair| pair.start_with?("tab=") }.join("&")
          "/hotel/#{params[:hotel_id]}/reports/tax_compliance#{extension}?tab=sst#{qs.present? ? "&#{qs}" : ""}"
        }
        get :non_national, to: redirect { |params, request|
          format = params[:format].to_s
          extension = format.present? ? ".#{format}" : ""
          qs = request.query_string.split("&").reject { |pair| pair.start_with?("tab=") }.join("&")
          "/hotel/#{params[:hotel_id]}/reports/tax_compliance#{extension}?tab=non_national#{qs.present? ? "&#{qs}" : ""}"
        }
      end
    end
    namespace :reports do
      resources :night_audits, only: [ :index, :show ]
    end
    resource :night_audit_run, only: [ :show, :create ] do
      get :status
      get :booking_timestamp
      get :force_close_confirmation
      post :start_review
      post :resolve_missing_folio
      post :resolve_missing_nightly_charges
      post :resolve_unsynced_payment
      post :resolve_unsynced_refund
      patch :resolve_booking_timestamp
      post :resolve_missed_arrival
      post :force_close
    end
    resources :night_audits, only: [ :index, :show ]
    resources :inventory_dashboards, only: [ :index ], path: "inventory" do
      collection do
        get :occupancy_details
        get :edit_selection
        post :apply_pricing_rules
        post :apply_availability_override
        post :bulk_save_ari
        post :batch_save_ari
        post :update_channel_derived_pricing
        post :create_channel_availability_rule
        delete "channel_availability_rules/:id", action: :destroy_channel_availability_rule, as: :destroy_channel_availability_rule
        delete "pricing_tiers/:rule_type", action: :destroy_pricing_tier_rule, as: :destroy_pricing_tier_rule
        delete "public_holidays/:id", action: :destroy_public_holiday_rule, as: :destroy_public_holiday_rule
      end
    end
    get "inventory", to: "inventory_dashboards#index", as: :inventory_index
    resources :guests, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
      collection do
        get :search
        get :check_banned
        delete :bulk_destroy
      end
      member do
        patch :toggle_vip
        patch :toggle_blacklist
      end
    end
    resources :in_house_guests, only: [ :index ]
    get "settings", to: "settings#show", as: :settings
    scope "settings" do
      get "general", to: "settings#index", as: :general_settings, defaults: { settings_page: "general" }
      patch "general", to: "settings#update", defaults: { settings_page: "general" }
      get "general/boat", to: "settings#index", as: :boat_settings, defaults: { settings_page: "boat" }
      patch "general/boat", to: "settings#update", defaults: { settings_page: "boat" }
      post "general/boat/slots", to: "boat_schedules#create", as: :boat_schedule_slots
      patch "general/boat/slots/:id", to: "boat_schedules#update", as: :boat_schedule_slot
      delete "general/boat/slots/:id", to: "boat_schedules#destroy"
      patch "general/boat/slots/:id/restore", to: "boat_schedules#restore", as: :boat_schedule_slot_restore
      get "general/rates", to: redirect("/hotel/%{hotel_id}/settings/property/room-inventory"), as: :rates_settings
      get "general/notifications", to: "settings#index", as: :notification_settings, defaults: { settings_page: "notifications" }
      patch "general/notifications", to: "settings#update", defaults: { settings_page: "notifications" }
      get "general/plan-and-billing", to: "plans#show", as: :plan

      scope "property" do
        patch "hotel-details", to: "profiles#update", as: :profile
        delete "hotel-details/photos/:photo_id", to: "profiles#destroy_photo", as: :profile_photo
        delete "hotel-details/photos", to: "profiles#destroy_photos", as: :profile_photos
        patch "hotel-details/photos/:photo_id/feature", to: "profiles#set_featured_photo", as: :profile_photo_feature
        post "hotel-details/photo-queue", to: "profiles#enqueue_photo", as: :profile_photo_queue
        delete "hotel-details/photo-queue", to: "profiles#clear_photo_queue", as: :clear_profile_photo_queue
        delete "hotel-details/photo-queue/:signed_id", to: "profiles#remove_photo_from_queue", as: :profile_photo_queue_item
        post "hotel-details/photo-queue/commit", to: "profiles#commit_photo_queue", as: :commit_profile_photo_queue

        get "room-categories", to: redirect("/hotel/%{hotel_id}/settings/property/room-inventory")
        get "room-categories/new", to: redirect("/hotel/%{hotel_id}/settings/property/room-inventory")
        get "room-categories/:id/edit", to: redirect("/hotel/%{hotel_id}/settings/property/room-inventory")

        resources :room_groups, path: "room-groups", except: :show
        resources :room_types, path: "room-inventory", except: [ :show ] do
          member do
            delete :destroy_photo
            delete :bulk_destroy_photos
          end
        end
        resource :room_group_assignment,
                 path: "room-inventory/room-group-assignment",
                 only: %i[new create]
        resources :rate_plan_attachments, path: "room-inventory/rate-plans", only: %i[new create] do
          get :autocomplete, on: :collection
        end
        resources :nearby_attractions, path: "nearby-attractions", except: [ :show ]
      end

      scope "finance" do
        get "banking-details", to: "settings#index", as: :banking_details_settings, defaults: { settings_page: "banking" }
        patch "banking-details", to: "settings#update", defaults: { settings_page: "banking" }
        resource :taxes_fees, path: "taxes-and-fees", only: [ :show, :update ]
        get "taxes-and-fees/system/:tax_key/edit", to: "taxes_fees#edit_system", as: :edit_system_tax
        patch "taxes-and-fees/system/:tax_key", to: "taxes_fees#update_system", as: :system_tax
        resources :hotel_taxes, path: "taxes-and-fees/fees", only: %i[index new create edit update destroy]
        get "transaction-code-reference", to: "transaction_code_references#index", as: :transaction_code_references
        resource :ota_financial_settings, path: "ota-financials", only: %i[show update] do
          post :approve_adjustment, on: :member
        end
        resources :general_ledger_maps, path: "general-ledger-mappings", only: [ :index, :edit, :update ]
      end

      scope "commercial" do
        resources :extra_charges, path: "extra-charges", only: %i[index new create edit update] do
          patch :status, action: :update_status, on: :member
        end
        resources :discounts, only: %i[index new create edit update] do
          patch :status, action: :update_status, on: :member
        end
        resources :payment_methods, path: "payment-methods", only: %i[index new create edit update] do
          patch :status, action: :update_status, on: :member
        end

        get "room-revenue", to: "room_revenue#show", as: :room_revenue
        patch "room-revenue/tax-rules", to: "room_revenue#update_tax_rules", as: :room_revenue_tax_rules
        patch "room-revenue/tax-rules/preview", to: "room_revenue#preview_tax_rules", as: :preview_room_revenue_tax_rules
        patch "room-revenue/configuration", to: "room_revenue#update_configuration", as: :room_revenue_configuration
        resources :reservation_policies, path: "room-revenue/reservation-policies", only: %i[edit update] do
          patch :status, action: :update_status, on: :member
        end
      end

      scope "guest-content" do
        get "ai-concierge", to: "settings#index", as: :ai_concierge_settings, defaults: { settings_page: "ai" }
        patch "ai-concierge", to: "settings#update", defaults: { settings_page: "ai" }
        resources :knowledge_policies, path: "policies" do
          member { post :reindex }
        end
        resources :knowledge_faqs, path: "faqs" do
          member { post :reindex }
        end
        resources :knowledge_general_infos, path: "general-info" do
          member { post :reindex }
        end
        resources :knowledge_diagnostics, path: "knowledge-diagnostics", only: [ :index, :update ]
      end

      scope "team" do
        # Revoke and reactivate collapsed into one status toggle on the listing
        # row; #update owns the role. DELETE is a permanent removal.
        resources :users, only: [ :index, :new, :create, :edit, :update, :destroy ], path: "staff" do
          patch :status, on: :member
        end
        resources :staff_invitations, path: "staff-invitations", only: [ :edit, :update, :destroy ] do
          post :resend, on: :member
        end
        resources :roles, only: [ :index, :new, :create, :edit, :update, :destroy ], path: "roles-and-permissions" do
          patch :bulk_update, on: :collection
        end
      end
    end

    # Legacy Settings URLs remain read-only redirects for existing bookmarks.
    get "settings/guest-content/notifications", to: redirect("/hotel/%{hotel_id}/settings/general/notifications")
    get "plan", to: redirect("/hotel/%{hotel_id}/settings/general/plan-and-billing")
    get "profile/edit", to: redirect("/hotel/%{hotel_id}/settings/property/hotel-details")
    get "room_types", to: redirect("/hotel/%{hotel_id}/settings/property/room-inventory")
    # New/edit are Sheets over the list now, so old deep links land on the list.
    get "room_types/new", to: redirect("/hotel/%{hotel_id}/settings/property/room-inventory")
    get "room_types/:id/edit", to: redirect("/hotel/%{hotel_id}/settings/property/room-inventory")
    get "nearby_attractions", to: redirect("/hotel/%{hotel_id}/settings/property/nearby-attractions")
    get "nearby_attractions/new", to: redirect("/hotel/%{hotel_id}/settings/property/nearby-attractions/new")
    get "nearby_attractions/:id/edit", to: redirect("/hotel/%{hotel_id}/settings/property/nearby-attractions/%{id}/edit")
    get "taxes-fees", to: redirect("/hotel/%{hotel_id}/settings/finance/taxes-and-fees")
    get "settings/finance/transaction-codes", to: redirect("/hotel/%{hotel_id}/settings/commercial/room-revenue")
    get "transaction-codes", to: redirect("/hotel/%{hotel_id}/settings/commercial/room-revenue")
    get "transaction-codes/new", to: redirect("/hotel/%{hotel_id}/settings/commercial/room-revenue")
    get "transaction-codes/:id/edit", to: redirect("/hotel/%{hotel_id}/settings/commercial/room-revenue")
    get "general-ledger-mappings", to: redirect("/hotel/%{hotel_id}/settings/finance/general-ledger-mappings")
    get "general-ledger-mappings/:id/edit", to: redirect("/hotel/%{hotel_id}/settings/finance/general-ledger-mappings/%{id}/edit")
    get "knowledge_policies", to: redirect("/hotel/%{hotel_id}/settings/guest-content/policies")
    get "knowledge_policies/new", to: redirect("/hotel/%{hotel_id}/settings/guest-content/policies/new")
    get "knowledge_policies/:id", to: redirect("/hotel/%{hotel_id}/settings/guest-content/policies/%{id}")
    get "knowledge_policies/:id/edit", to: redirect("/hotel/%{hotel_id}/settings/guest-content/policies/%{id}/edit")
    get "knowledge_faqs", to: redirect("/hotel/%{hotel_id}/settings/guest-content/faqs")
    get "knowledge_faqs/new", to: redirect("/hotel/%{hotel_id}/settings/guest-content/faqs/new")
    get "knowledge_faqs/:id", to: redirect("/hotel/%{hotel_id}/settings/guest-content/faqs/%{id}")
    get "knowledge_faqs/:id/edit", to: redirect("/hotel/%{hotel_id}/settings/guest-content/faqs/%{id}/edit")
    get "knowledge_general_infos", to: redirect("/hotel/%{hotel_id}/settings/guest-content/general-info")
    get "knowledge_general_infos/new", to: redirect("/hotel/%{hotel_id}/settings/guest-content/general-info/new")
    get "knowledge_general_infos/:id", to: redirect("/hotel/%{hotel_id}/settings/guest-content/general-info/%{id}")
    get "knowledge_general_infos/:id/edit", to: redirect("/hotel/%{hotel_id}/settings/guest-content/general-info/%{id}/edit")
    get "knowledge_diagnostics", to: redirect("/hotel/%{hotel_id}/settings/guest-content/knowledge-diagnostics")
    get "staff", to: redirect("/hotel/%{hotel_id}/settings/team/staff")
    # Invite is a Sheet over the list now, so the old deep link lands on the list.
    get "staff/new", to: redirect("/hotel/%{hotel_id}/settings/team/staff")
    get "roles-and-permissions", to: redirect("/hotel/%{hotel_id}/settings/team/roles-and-permissions")
    # New/edit are Sheets over the matrix now, so old deep links land on it.
    get "roles-and-permissions/new", to: redirect("/hotel/%{hotel_id}/settings/team/roles-and-permissions")
    get "roles-and-permissions/:id/edit", to: redirect("/hotel/%{hotel_id}/settings/team/roles-and-permissions")

    resource :concierge_qr, only: [ :show ], controller: "concierge_qr"
    # Wizard bookmarks now land on the single-room rate-plan sheet.
    get "rate_plans/wizard", to: redirect("/hotel/%{hotel_id}/rate_plans/new")
    get "rate_plans/wizard/:step", to: redirect("/hotel/%{hotel_id}/rate_plans/new")

    resources :rate_plans, only: %i[new create edit update destroy] do
      resources :room_pricings,
        only: %i[edit update destroy],
        param: :room_type_id,
        controller: "rate_plan_room_pricings"
      member do
        patch :archive
        patch :unarchive
      end
    end
    resources :inventory_audit_logs, only: [ :index ]
    resources :global_search, only: [ :index ]
  end
end
